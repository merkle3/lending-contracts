// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "forge-std/console.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAssetClass} from './interfaces/IAssetClass.sol';
import {IDebtMarket} from './interfaces/IDebtMarket.sol';
import {IController} from './interfaces/IController.sol';
import {IMerkleLiquidator} from './interfaces/IMerkleLiquidator.sol';
import {Rewards} from './rewards/Rewards.sol';

/**
 The controller makes sure users are solvant when
 borrowing or depositing collaterals.
 */
contract Controller is Ownable, Pausable, IController {
    // we need to be able to register asset classes
    address[] public assetClassesList;

    // we need to be able to register token markets
    address[] public debtMarketsList;

    // maximum collateral usability (80%)
    uint256 constant maxCollateralUsability = 8_000;

    // 20% by default
    uint platformFees = 2_000; // = 20%, 100 = 1%

    // events
    event Liquidation(address indexed account, address[] markets, uint256[] assets);
    event TokenMarketAdded(address indexed tokenMarket);
    event AssetClassAdded(address indexed assetClass);

    constructor() {
        // register owner
        transferOwnership(msg.sender);
    }

    // returns the total of token markets registered
    function totalDebtMarkets() external view returns (uint) {
        return debtMarketsList.length;
    }

    // return the count of asset classes registered
    function totalAssetClasses() external view returns (uint) {
        return assetClassesList.length;
    }

    // add a new asset class
    function addAssetClass(address assetClass) external onlyOwner {
        // add asset class to list
        assetClassesList.push(assetClass);

        // event
        emit AssetClassAdded(assetClass);
    }

    // add a new market
    function addDebtMarket(address market) external onlyOwner {
        // add market to list
        debtMarketsList.push(market);

        // event
        emit TokenMarketAdded(market);
    }

    // return platform fee
    function platformFee() external override view returns(uint) {
        return platformFees;
    }

    // set the platform fee
    function setPlatformFee(uint256 fee) external onlyOwner {
        platformFees = fee;
    }

    // get the total amount of collateral the user has put up
    function getTotalCollateral(address account) view public returns(uint256) {
        // get the total collateral
        uint totalCollateralForAccount = 0;

        for(uint24 i = 0; i < assetClassesList.length; i++) {
            // add up all the collateral from all asset classes
            totalCollateralForAccount += IAssetClass(assetClassesList[i]).getTotalCollateralUsd(account);
        }

        return totalCollateralForAccount;
    }

    /**
     * Get the total amount a user has borrowed from the token market
     * @param account the user
     * @return the total amount borrowed in USD
     */
    function getTotalBorrow(address account) public returns(uint256) {
        uint totalBorrowForAccount = 0;

        for(uint24 i = 0; i < debtMarketsList.length; i++) {
            // add up all the borrowing from all token markets
            totalBorrowForAccount += IDebtMarket(debtMarketsList[i]).getDebtBalanceUsd(account);
        }

        return totalBorrowForAccount;
    }

    // checks if account is healthy
    function isHealthy(address account) external override returns(bool) {
        uint256 totalCollateral = getTotalCollateral(account);
        uint256 totalBorrow = getTotalBorrow(account);

        // calculate 80% of collateral
        uint256 maxBorrow = totalCollateral * maxCollateralUsability / 10_000;

        return totalBorrow <= maxBorrow;
    }

    // buy assets from account to repay debts
    function buyAssets(address account, address[] calldata assetClass, uint256[] calldata tokenId, address liquidator, bytes memory data) external override returns (bool) {
        require(!this.isHealthy(account), "Account is healthy, cannot liquidate");

        // transfer assets to liquidator
        for (uint i = 0; i < assetClass.length; i++) {
            // transfer the asset to the liquidator
            IAssetClass(assetClass[i]).transferAsset(account, msg.sender, tokenId[i]);
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
        require(this.isHealthy(account), "Account is unhealthy after liquidation");

        // emit event for liquidation
        emit Liquidation(account, assetClass, tokenId);

        return true;
    }  

    /// @notice pending rewards from all vaults
    /// @param account the account
    function getPendingRewards(address account) external returns (uint256 totalRewards) {
        totalRewards = 0;

        for(uint24 i = 0; i < debtMarketsList.length; i++) {
            // add up all the collateral from all asset classes
            totalRewards += Rewards(debtMarketsList[i]).getPendingRewards(account);
        }
    }

    /// @notice collect reward from all vaults
    /// @param recipient the recipient of the rewards
    function claimRewards(address recipient) external returns (uint256 totalRewards) {
        totalRewards = 0;

        for(uint24 i = 0; i < assetClassesList.length; i++) {
            // add up all the collateral from all asset classes
            Rewards(assetClassesList[i]).claimRewards(recipient);
        }
    }
}