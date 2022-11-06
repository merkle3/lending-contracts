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

/**
 The controller makes sure users are solvant when
 borrowing or depositing collaterals.
 */
contract Controller is Ownable, Pausable, IController {
    using FixedPointMathLib for uint256;

    // list of debt markets
    address[] public debtMarketsList;

    // maximum collateral usability (80%)
    uint256 constant collateralDefaultRate = 8_000;

    // specific rates for markets
    mapping(address => uint256) public collateralRates;

    // disabled markets
    mapping(address => bool) public disabledMarkets;

    // 20% by default
    uint platformFees = 2_000; // = 20%, 100 = 1%

    // events
    event Liquidation(address indexed account, address markets);
    event DebtMarketAdded(address indexed tokenMarket);

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

    // get the total amount of collateral the user has put up
    function getTotalCollateralUsd(address account) view public returns(uint256) {
        // get the total collateral
        uint totalCollateralForAccount = 0;

        for(uint24 i = 0; i < debtMarketsList.length; i++) {
            // by default, we allow a certain usage of collateral
            uint256 rate = collateralRates[debtMarketsList[i]];

            if (rate == 0) {
                // for some markets, we might want to have less
                // exposure to collateral
                rate = collateralDefaultRate;
            }

            // if disabled, don't call it
            if (disabledMarkets[debtMarketsList[i]]) {
                continue;
            }

            // add up all the collateral from all asset classes
            totalCollateralForAccount += IDebtMarket(debtMarketsList[i]).getCollateralUsd(account).mulDivDown(rate, 10_000);
        }

        return totalCollateralForAccount;
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
        uint256 totalCollateral = getTotalCollateralUsd(account);
        uint256 totalBorrow = getTotalBorrowUsd(account);        

        return totalBorrow <= totalCollateral;
    }

    // buy assets from account to repay debts
    function liquidate(address account, address[] calldata markets, bytes[] calldata datas, address liquidator, bytes memory data) external override {
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
        // add market to list
        debtMarketsList.push(market);

        // event
        emit DebtMarketAdded(market);
    }

    /// @notice set the platform fee
    /// @param fee the fee in basis points
    function setPlatformFee(uint256 fee) external onlyOwner {
        platformFees = fee;
    }

    /// @notice set the collateral rate for this market
    /// @param market the market to set the rate of
    function setCollateralRate(address market, uint256 rate) external onlyOwner {
        collateralRates[market] = rate;
    }
    
    /// @notice set the disable state for a market
    /// @param market the market to disable/re-able
    function setDisabledMarket(address market, bool disabled) external onlyOwner {
        disabledMarkets[market] = disabled;
    }
}