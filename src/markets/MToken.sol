// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";

import {ERC4626} from "../generics/ERC4626.sol";
import {MTokenMarket} from '../interfaces/MTokenMarket.sol';
import {IController} from '../interfaces/IController.sol';
import {IInterestModel} from '../interest/IInterestModel.sol';
import {Rewards} from '../rewards/Rewards.sol';
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC3156FlashBorrower} from '../interfaces/IERC3156FlashBorrower.sol';
import {IERC3156FlashLender} from '../interfaces/IERC3156FlashLender.sol';
import {AggregatorV3Interface} from '../interfaces/AggregatorV3Interface.sol';
import {FixedPointMathLib} from '../libraries/FixedPointMathLib.sol';

contract MToken is MTokenMarket, IERC3156FlashLender, Ownable, Pausable, Rewards {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using SafeMath for uint;

    // oracle for the underlying asset
    address public immutable oracle;

    // interest model
    address public interestModel;

    // total borrow shares
    uint totalBorrowShares;

    // total borrow 
    uint public totalBorrows;

    // cash reverves
    uint public cashReserves;
    
    // borrowed shares by address
    mapping(address => uint) public borrowed;

    // controller
    address _controller;

    // to calculate interest
    uint public constant secondsPerYear = 31_540_000;

    // flashloan fee (0.01%)
    uint constant flashloanFee = 1;

    // x% of all interest goes to platform
    uint public collectableFee = 0;

    // the address allowed to collect fees
    address public feeCollector;

    // used for computations
    uint constant expScale = 1e18;

    // last block that interest was updated
    uint lastAccrualOfInterest = 0;

    // token scale
    uint tokenScale;

    constructor(
        address controller, 
        address assetAddress, 
        address _oracle,
        address _interestModel,
        uint _tokenScale
        // TODO: set reward token
        // reward 5M tokens over 3 years
        // 3 years = 94608000 seconds
        /// 5M = 5000000000000000000000000 WEI
    ) ERC4626(ERC20(assetAddress), "Merkle USDC", "mUSDC") Rewards(ERC20(address(0)), block.timestamp, 5000000000000000000000000, 94608000) {
        _controller = controller;
        lastAccrualOfInterest = block.timestamp;
        oracle = _oracle;
        interestModel = _interestModel;
        feeCollector = msg.sender;
        tokenScale = _tokenScale;

        // register owner
        transferOwnership(msg.sender);
    }

    // --------- ADMIN FUNCTIONS -------

    /// @notice update the interest model for this vault
    /// @param model the new interest model
    function setInterestModel(address model) public onlyOwner {
        interestModel = model;
    }

    /// @notice collect the platform fee
    /// @param amount the amount to collect
    function collectFee(uint amount) public onlyOwner {
        require(amount <= collectableFee, "amount too high");

        // update collectable fee
        collectableFee -= amount;

        // transfer asset to fee collector
        asset.safeTransfer(feeCollector, amount);
    }

    /// @notice override max withdraw based on cash reserves
    /// @param owner the account of the LP
    function maxWithdraw(address owner) public override view virtual returns (uint256) {
        uint ownerAssets = convertToAssets(balanceOf(owner));

        return ownerAssets > cashReserves ? cashReserves : ownerAssets;
    }

    /// @notice maximum redeemable based on cash reserves
    /// @param owner the account of the LP
    function maxRedeem(address owner) public override view virtual returns (uint256) {
        uint maxShares = this.convertToShares(cashReserves); // saves a SLOAD
        uint shares = balanceOf(owner); // saves a SLOAD

        return shares > maxShares ? maxShares : shares;
    }

    /// @notice total assets are lended assets and reserves
    function totalAssets() public override view virtual returns (uint256) {
        return cashReserves + totalBorrows;
    }

    /// @notice override the function that updates interest
    function updateInterest() internal virtual override {
        this.accrueInterest();
    }

    /// @notice return the balance in usd 
    /// @param borrower the borrower whose balance to check
    function getBorrowBalanceUsd(address borrower) override public returns (uint256) {
        this.accrueInterest();

        AggregatorV3Interface tokenAggr = AggregatorV3Interface(oracle);

        (,int256 rate,,,) = tokenAggr.latestRoundData();

        // chainlink oracles return 8 decimals quotes
        return this.getBorrowBalance(borrower).mulDivUp(uint256(rate), tokenScale);
    }
    
    /// @notice return the balance in underlying asset
    /// @param account the borrower whose balance to check
    function getBorrowBalance(address account) external returns (uint256) {
        this.accrueInterest();

        return borrowed[account].mulDivUp(getBorrowRate(), expScale);
    }

    // ----- REWARD FUNCTIONS -----
    /// @notice override the reward function to accrue interest
    function totalRewardSupplyBasis() external override returns (uint256) {
        this.accrueInterest();

        // total borrows is both owned by lenders and borrowers
        return (totalBorrows*2) + cashReserves;
    }

    /// @notice how much of the reward is owned by the user
    /// @param account the user whose reward to check
    function rewardSupplyBasis(address account) external virtual override returns (uint256) {
        this.accrueInterest();

        return convertToAssets(balanceOf(account)) + this.getBorrowBalance(account);
    }

    // ----- INTEREST FUNCTIONS ----

    /// @notice accrue interest over all loands 
    // that the vault gave out
    function accrueInterest() external returns(uint interestedCharged) {
        if (block.timestamp == lastAccrualOfInterest) {
            // no update to be made
            return 0;
        }

        if(totalBorrows == 0) {
            // no borrows, no interest
            return 0;
        }

        // get the current APY
        uint currentAPY = this.getInterest();

        // 1 + APY / 100 = percentage multiplier
        // currentAPY to % =/ 10_000 
        uint apy = (currentAPY * expScale / 10_000);

        // calculate share of APY for the period
        uint periodInSeconds = block.timestamp - lastAccrualOfInterest;

        uint yearInterest = totalBorrows * apy / expScale;

        // calculate amount to add to debt based on total borrows
        uint interestCharged = yearInterest * periodInSeconds / secondsPerYear;

        // calculate platform fee
        uint platformFeeCharged = interestCharged.mulDivDown(IController(_controller).platformFee(), 10000);

        // adds interest to debt
        totalBorrows += interestCharged - platformFeeCharged;

        // add fees to collect
        collectableFee += platformFeeCharged;

        // set last accrual of interest
        lastAccrualOfInterest = block.timestamp;
    } 

    /// @notice returns the APY in exponential form
    /// @dev this method calls the interest model
    function getInterest() external view returns (uint) {
        // call the interest model to get the current APY
        return IInterestModel(interestModel).getBorrowRate(cashReserves, totalBorrows);
    }

    // ----- BORROW Functions -----

    /// @notice returns the rate between borrow shares and borrow amount
    /// @return rate the exchange rate between borrow shares and total amouunt borrowed
    function getBorrowRate() public returns (uint) {
        // accrue interest
        this.accrueInterest();

        if(totalBorrowShares == 0) {
            return expScale;
        }

        uint borrowExchangeRate = totalBorrows.mulDivUp(expScale, totalBorrowShares);

        return borrowExchangeRate;
    }

    // ------- BORROW and REPAY -------
    /// @notice borrow from the vault
    /// the vault will issue a set of "loan shares" to the borrower
    /// which represents how much of the total loan of the vault 
    /// they are reponsible for.
    /// @param amountUnderlying the amount to borrow
    /// @param receiver the account to receive the loaned underlying amount
    function borrow(uint256 amountUnderlying, address receiver) override external updateReward(msg.sender) whenNotPaused {
        // check if there is enough cash
        require(cashReserves >= amountUnderlying, "NO_RESERVES");

        // don't send to zero address
        require(receiver != address(0), "INVALID_RECEIVER");
        
        // get the current borrow rate
        uint borrowRate = getBorrowRate();

        // issue borrow shares
        uint borrowShares = amountUnderlying * expScale / borrowRate;

        // update borrower's share of the total borrow
        borrowed[msg.sender] += borrowShares;

        // update the total amount of shares
        totalBorrowShares += borrowShares;

        // add to total borrow
        totalBorrows += amountUnderlying;

        // update cash reserves
        cashReserves -= amountUnderlying;

        // require that user is healthy
        require(IController(_controller).isHealthy(msg.sender), "NOT_HEALTHY");

        // transfer to recipient
        asset.transfer(receiver, amountUnderlying);
    }

    /// @notice repay a loan
    /// @param account the account to repay
    /// @param amountUnderlying the amount to repay
    function repay(address account, uint256 amountUnderlying) override external updateReward(account) {
         // calculate reserves
        this.accrueInterest();

        // get exchange rate from borrow shares to underlying
        uint rate = getBorrowRate();

        // get the loan shares that are being repayed
        uint borrowShares = amountUnderlying.mulDivUp(expScale, rate);

        // prevent overpaying
        require(borrowed[account] >= borrowShares, "OVER_PAID");

        // transfer the amount to vault
        asset.safeTransferFrom(account, address(this), amountUnderlying);

        // update total borrow
        // prevent underflow
        totalBorrows = totalBorrows.sub(amountUnderlying);

        // update cash reserves
        cashReserves = cashReserves.add(amountUnderlying);

        // update user's borrow
        borrowed[account] = borrowed[account].sub(borrowShares);
        totalBorrowShares = totalBorrowShares.sub(borrowShares);
    }

    /// @notice repay shares instead of underlying asset
    /// this is very useful for repaying the entire debt as it's
    /// hard to get the ratio perfectly due to rounding errors and
    /// interest being calculated at every block.
    /// @param account the account to repay
    /// @param shares the amount of shares to repay
    function repayShares(address account, uint256 shares) external updateReward(account) {
         // calculate reserves
        this.accrueInterest();

        // get exchange rate from borrow shares to underlying
        uint rate = getBorrowRate();

        // calculate how much it will be
        uint amountUnderlying = shares.mulDivUp(rate, expScale);

        // prevent underflow
        if (amountUnderlying > totalBorrows) {
            amountUnderlying = totalBorrows;
        }
        
        // prevent overpaying
        require(borrowed[account] >= shares, "OVER_PAID");

        // transfer the amount to vault
        asset.safeTransferFrom(account, address(this), amountUnderlying);

        // update total borrow
        totalBorrows = totalBorrows.sub(amountUnderlying);

        // update cash reserves
        cashReserves = cashReserves.add(amountUnderlying);

        // update user's borrow
        borrowed[account] =  borrowed[account].sub(shares);
        totalBorrowShares = totalBorrowShares.sub(shares);
    }

    // ------- Deposit functions -------
    
    /// @notice get the usd value of deposits for a LP
    /// @param depositor the LP account
    function getDepositBalanceUsd(address depositor) public returns (uint256) {
        this.accrueInterest();

        // get the quote from chainlink
        AggregatorV3Interface tokenAggr = AggregatorV3Interface(oracle);

        (,int256 rate,,,) = tokenAggr.latestRoundData();

        // get the underling amount for the deposit
        uint assetAmount = this.convertToAssets(this.balanceOf(depositor));

        // chain link quotes are 8 decimals
        return assetAmount * uint256(rate) / tokenScale;
    }

    /// @notice make sure we have enough assets
    function beforeWithdraw(uint assets, uint256 /*shares*/) override internal virtual updateReward(msg.sender) { 
        require(cashReserves >= assets, "NO_RESERVES");
    }

    /// @notice update the rewards before a deposit
    function beforeDeposit(uint assets, uint256 shares) override internal virtual updateReward(msg.sender) { 
        /// just update the rewards
    }

    /// @notice update the cash reserves after a deposit
    function afterDeposit(uint256 assets, uint256 /*shares*/) override internal virtual {
        // update the cash reserves
        cashReserves = cashReserves + assets;
    }

    /// @notice update the cash reserves after withdraw
    function afterWithdraw(uint256 assets, uint256 /*shares*/) override internal virtual {
        // update the cash reserves
        cashReserves = cashReserves - assets;
    }

    // ------- Flash Loan provider (ERC3156) --------

    /// @notice The amount of currency available to be lent.
    /// @param token The loan currency.
    /// @return The amount of `token` that can be borrowed.
    function maxFlashLoan(
        address token
    ) override external view returns (uint256) {
        if(token != address(asset)) return 0;

        return cashReserves;
    }

    /// @notice The fee to be charged for a given loan.
    /// @param token The loan currency.
    /// @param amount The amount of tokens lent.
    /// @return The amount of `token` to be charged for the loan, on top of the returned principal.
    function flashFee(
        address token,
        uint256 amount
    ) override external view returns (uint256) {
        if(token != address(asset)) return 0;

        return amount * flashloanFee / 10000;
    }

    /// @notice Initiate a flash loan.
    /// @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
    /// @param token The loan currency.
    /// @param amount The amount of tokens lent.
    /// @param data Arbitrary data structure, intended to contain user-defined parameters.
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) override external returns (bool) {
        if(token != address(asset)) revert("Token not supported");

        // calculate the fee
        uint fee = amount * flashloanFee / 10000;

        // check that the cash reserves are enough
        require(amount <= cashReserves, "Not enough cash reserves");

        // transfer the cash reserves to the borrower
         asset.transferFrom(
            address(this),
            address(receiver),
            amount
        );

        uint balanceBefore =  asset.balanceOf(address(this));

        // call the callback
        receiver.onFlashLoan(
            msg.sender,
            token,
            amount,
            fee,
            data
        );

        // make sure we got repayed
        uint balanceAfter =  asset.balanceOf(address(this));

        // make sure we got repayed
        require(balanceAfter >= balanceBefore + fee, "Not enough repayed");

        // add it to cash reserves (should be just fee but can be more)
        cashReserves += balanceAfter - balanceBefore;

        return true;
    }
}