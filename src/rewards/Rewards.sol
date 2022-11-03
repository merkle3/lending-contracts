// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";

// this contract is a generic interface for awarding rewards
// for a share of a vault
abstract contract Rewards {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // reward per second
    uint256 public rewardPerSecond;

    // total reward to distribute
    uint256 public totalReward;

    // the timestamp when reward started
    uint256 public startTimestamp;
    
    // the timestamp when reward ends
    uint256 public endTimestamp;

    // user info
    struct UserInfo {
        // how many shares the user has
        uint256 shares;
        // the shares of reward has claimed
        // or reward that were earned before the user joined
        uint256 rewardDistributed; 
    }

    // user info map
    mapping(address => UserInfo) public userInfo;

    // total rewards
    uint256 public rewardsPerShare;

    // the reward token
    ERC20 public rewardToken;

    // last time the reward was updated
    uint256 public lastRewardTimestamp;

    /// @notice the contructor that takes a token and a reward flow rate
    /// @param _rewardToken the reward token
    /// @param _totalRewards the total rewards
    /// @param _rewardDuration the period of rewards
    constructor(ERC20 _rewardToken, uint256 start, uint256 _totalRewards, uint256 _rewardDuration) {
        // start now
        startTimestamp = start;

        rewardToken = _rewardToken;
        rewardPerSecond = _totalRewards / _rewardDuration;
        endTimestamp = startTimestamp + _rewardDuration;
        lastRewardTimestamp = startTimestamp;
    }

    // a function that returns the total reward supply
    function totalRewardSupplyBasis() external virtual returns (uint256);

    // a function that returns how much of the reward supply
    // is available for a given account
    function rewardSupplyBasis(address account) external virtual returns (uint256);

    /// @notice update the rewards for an account
    /// @param account the account to update
    modifier updateReward(address account) {
        if(block.timestamp < startTimestamp || lastRewardTimestamp > endTimestamp) {
            // no rewards outside of period
            _;
        } else {
            // we bound the rewards to the end timestamp
            uint256 endBoundTimestamp = block.timestamp;

            if (endBoundTimestamp > endTimestamp) {
                endBoundTimestamp = endTimestamp;
            }

            // calculate reward
            uint256 secondsDelta = block.timestamp - lastRewardTimestamp;

            // update the last timestamp for rewards
            lastRewardTimestamp = block.timestamp;

            // add the reward per share
            rewardsPerShare += rewardsPerShareForTimeDelta(secondsDelta);

            // do the function
            _;

            // check the user info
            UserInfo storage user = userInfo[account];

            // shares owned by the user
            uint256 shares = this.rewardSupplyBasis(account);
            
            // if user had deposited
            if (user.shares == 0) {
                // set the user shares to the supply basis
                user.shares = shares;

                // set the reward debt to not collect rewards from other members
                user.rewardDistributed = rewardsPerShare * shares;
            }

            // update the shares
            user.shares = shares;
        }
    }

    function rewardsPerShareForTimeDelta(uint256 timeDelta) internal returns (uint256) {
        // calculate the rewards per share
        uint256 totalSupply = this.totalRewardSupplyBasis();

        // the total reward in that period
        uint256 totalRewardForDelta = timeDelta * rewardPerSecond;

        if (totalSupply == 0) {
            return totalRewardForDelta;
        } else {
            return totalRewardForDelta / totalSupply;
        }
    }  

    /// @notice return the pending rewards
    /// @param account the account to check
    function getPendingRewards(address account) external virtual view returns (uint256) {
        // check the user info
        UserInfo storage user = userInfo[account];

        // the current reward per share minus the reward debt
        uint256 owned = user.shares * rewardsPerShare - user.rewardDistributed;

        // return the owned shares
        return owned;
    }

    /// @notice allows an account to claim the rewards
    /// @param rewardAmount the shares of rewards to claim
    /// @param recipient the recipient of the rewards
    function claimRewards(uint256 rewardAmount, address recipient) external virtual updateReward(msg.sender) {
        // the user info
        UserInfo storage user = userInfo[msg.sender];

        // check the user info
        uint256 pendingRewards = this.getPendingRewards(msg.sender);        

        // make sure we don't claim too much
        require(pendingRewards >= rewardAmount, "Rewards: not enough rewards");

        // update the reward balance
        user.rewardDistributed += rewardAmount;

        // transfer the rewards
        rewardToken.safeTransfer(recipient, rewardAmount);
    }
}