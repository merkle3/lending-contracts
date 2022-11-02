// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "forge-std/console.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAssetClass} from './interfaces/IAssetClass.sol';
import {MTokenMarket} from './interfaces/MTokenMarket.sol';
import {IController} from './interfaces/IController.sol';
import {Rewards} from './rewards/Rewards.sol';

/**
 The controller makes sure users are solvant when
 borrowing or depositing collaterals.
 */
contract Controller is Ownable, Pausable, IController {
    // we need to be able to register asset classes
    address[] public assetClassesList;

    // we need to be able to register token markets
    address[] public tokenMarketsList;

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
    function totalTokenMarkets() external view returns (uint) {
        return tokenMarketsList.length;
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
    function addMarket(address market) external onlyOwner {
        // add market to list
        tokenMarketsList.push(market);

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

        for(uint24 i = 0; i < tokenMarketsList.length; i++) {
            // add up all the borrowing from all token markets
            totalBorrowForAccount += MTokenMarket(tokenMarketsList[i]).getBorrowBalanceUsd(account);
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
    function buyAssets(address account, address[] calldata assetClass, uint256[] calldata tokenId) external override returns (bool) {
        require(!this.isHealthy(account), "Account is healthy, cannot buy assets");

        // transfer assets to liquidator
        for (uint i = 0; i < assetClass.length; i++) {
            // transfer the asset to the liquidator
            IAssetClass(assetClass[i]).transferAsset(account, msg.sender, tokenId[i]);
        }

        // make sure the account is healthy afterwards
        require(this.isHealthy(account), "Account is unhealthy after sell");

        // emit event for liquidation
        emit Liquidation(account, assetClass, tokenId);

        return true;
    }  

    /// @notice pending rewards from all vaults
    /// @param account the account
    function getPendingRewards(address account) external view returns (uint256 totalRewards) {
        totalRewards = 0;

        for(uint24 i = 0; i < tokenMarketsList.length; i++) {
            // add up all the collateral from all asset classes
            totalRewards += Rewards(tokenMarketsList[i]).getPendingRewards(account);
        }
    }

    /// @notice collect reward from all vaults
    /// @param rewardAmount the shares of rewards to claim
    /// @param recipient the recipient of the rewards
    function claimRewards(uint256 rewardAmount, address recipient) external returns (uint256 totalRewards) {
        totalRewards = 0;

        for(uint24 i = 0; i < assetClassesList.length; i++) {
            // add up all the collateral from all asset classes
            Rewards(assetClassesList[i]).claimRewards(rewardAmount, recipient);
        }
    }
}