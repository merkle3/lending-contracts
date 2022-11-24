// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "forge-std/console.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IDebtMarket} from './interfaces/IDebtMarket.sol';
import {FixedPointMathLib} from './libraries/FixedPointMathLib.sol';
import {IController} from './interfaces/IController.sol';
import {IMerkleLiquidator} from './interfaces/IMerkleLiquidator.sol';
import {Rewards} from './rewards/Rewards.sol';
import {Lockable} from './utils/Lockable.sol';

/**
 The controller makes sure users are solvant when
 borrowing or depositing collaterals.
 */

// TODO: put a re-entrency lock on functions with callbacks

contract Controller is Ownable, Lockable, IController {
    using FixedPointMathLib for uint256;

    // list of debt markets
    address[] public debtMarketsList;

    // map of markets
    mapping(address => bool) public debtMarkets;

    // disabled markets
    mapping(address => bool) public disabledMarkets;

    // 30% by default
    uint platformFees = 3_000; // = 30%, 100 = 1%

    // events
    event Liquidation(address indexed account, address markets);
    event DebtMarketAdded(address indexed tokenMarket);
    event CollateralRateChanged(address indexed tokenMarket, uint256 rate);
    event MarketDisabled(address indexed tokenMarket, bool disabled);
    event PlatformFeeChanged(uint256 fee);

    constructor() {
        // register owner
        transferOwnership(msg.sender);
    }

    // return the count of asset classes registered
    function totalDebtMarkets() external view returns (uint) {
        return debtMarketsList.length;
    }

    // return platform fee
    function platformFee() external override view returns(uint) {
        return platformFees;
    }

    // get the total amount an account is allowed to borrow
    function getMaxBorrowUsd(address account) view public returns(uint256) {
        // get the total amount
        uint maxBorrowAmount = 0;

        for(uint24 i = 0; i < debtMarketsList.length; i++) {
            // add up all the debt market borrow authorization
            maxBorrowAmount += IDebtMarket(debtMarketsList[i]).getMaxBorrowUsd(account);
        }

        return maxBorrowAmount;
    }

    // get the total amount of collateral the user has put up
    function getTotalDepositsUsd(address account) view public returns(uint256) {
        // get the total deposits
        uint totalDepositsForAccount = 0;

        for(uint24 i = 0; i < debtMarketsList.length; i++) {
            // add up all the deposits from all the debt markets
            totalDepositsForAccount += IDebtMarket(debtMarketsList[i]).getCollateralUsd(account);
        }

        return totalDepositsForAccount;
    }

    /**
     * Get the total amount a user has borrowed from the token market
     * @param account the user
     * @return the total amount borrowed in USD
     */
    function getTotalBorrowUsd(address account) public returns(uint256) {
        uint totalBorrowForAccount = 0;

        for(uint24 i = 0; i < debtMarketsList.length; i++) {
            // add up all the borrowing from all token markets
            totalBorrowForAccount += IDebtMarket(debtMarketsList[i]).getDebtBalanceUsd(account);
        }

        return totalBorrowForAccount;
    }

    // checks if account is healthy
    function isHealthy(address account) external override returns(bool) {
        uint256 maxBorrow = getMaxBorrowUsd(account);
        uint256 totalBorrow = getTotalBorrowUsd(account);        

        // max borrow can be zero, in this case the 
        // account needs to be healthy
        return totalBorrow <= maxBorrow;
    }

    // buy assets from account to repay debts
    function liquidate(address account, address[] calldata markets, bytes[] calldata datas, address liquidator, bytes memory data) lock external override {
        require(!this.isHealthy(account), "CANNOT_LIQUIDATE");

        // transfer assets to liquidator
        for (uint i = 0; i < markets.length; i++) {
            address market = markets[i]; // save a SLOAD

            // transfer the asset to the liquidator
            IDebtMarket(market).liquidate(account, msg.sender, datas[i]);

            // emit event for liquidation
            emit Liquidation(account, market);
        }

        // call the callback on the liquidator
        try IMerkleLiquidator(liquidator).onMerkleLiquidation(
            account,
            data
        ) returns (bytes4 retval) {
            require(
                retval == IMerkleLiquidator.onMerkleLiquidation.selector,
                "IMerkleLiquidator: liquidator not implemented"
            );
        } catch {
            revert("IMerkleLiquidator: liquidator callback failed");
        }

        // make sure the account is healthy afterwards
        require(this.isHealthy(account) == true, "ACCOUNT_UNHEALTHY");
    }

    /// ------ ADMIN FUNCTIONS ---- 
    /// @notice add a new market
    /// @param market the market to add
    function addDebtMarket(address market) external onlyOwner {
        // make sure the market doesn't exist
        require(debtMarkets[market] == false, "MARKET_EXISTS");

        // add market to list
        debtMarketsList.push(market);

        // mark the map
        debtMarkets[market] = true;

        // event
        emit DebtMarketAdded(market);
    }

    /// @notice set the platform fee
    /// @param fee the fee in basis points
    function setPlatformFee(uint256 fee) external onlyOwner {
        // update the fee
        platformFees = fee;

        // emit
        emit PlatformFeeChanged(fee);
    }
    
    /// @notice set the disable state for a market
    /// @param market the market to disable/re-able
    function setDisabledMarket(address market, bool disabled) external onlyOwner {
        // make sure the market exists
        require(debtMarkets[market] == true, "MARKET_NOT_EXISTS");

        // update the status of the market
        disabledMarkets[market] = disabled;

        // emit
        emit MarketDisabled(market, disabled);
    }
}