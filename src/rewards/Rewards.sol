// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// this contract is a generic interface for awarding rewards
// for a share of a vault
abstract contract Rewards is Ownable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // reward per second
    uint256 public rewardPerSecond;

    // total reward to distribute
    uint256 public totalRewards;

    // total rewards distributed via transfers
    // this is not pending rewards
    uint256 public totalRewardsPaid;

    // the timestamp when reward started
    uint256 public startTimestamp;
    
    // the timestamp when reward ends
    uint256 public endTimestamp;

    // we scale up rewards per share for much more accuracy on small time scales
    uint256 private rewardExpScale = 1e36;

    // user info
    struct UserInfo {
        // how many shares the user has
        uint256 shares;
        // the shares of reward has claimed
        // or reward that were earned before the user joined
        uint256 rewardDistributed; 
        // rewards owed to the user, but not yet distributed
        // this happens if the user reduces or increases
        // their share amount
        uint256 owedRewards;
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
        // start at a specific time
        startTimestamp = start;

        // the ERC20 token to distribute
        rewardToken = _rewardToken;

        // the reward per second
        rewardPerSecond = _totalRewards / _rewardDuration;

        // the total rewards, we are re-calculating in 
        // case of precision loss from the previous divison
        totalRewards = rewardPerSecond * _rewardDuration;

        // the end timestamp of the reward period
        endTimestamp = startTimestamp + _rewardDuration;

        // set the last reward timestamp
        lastRewardTimestamp = 0;

        // transfer ownership
        transferOwnership(msg.sender);
    }

    /// @notice calculate the amount of reward per share over a time period
    /// @param timeDelta the time period
    /// @return totalRewardForDelta amount of reward per share
    function rewardsPerShareForTimeDelta(uint256 timeDelta) internal returns (uint256 totalRewardForDelta) {
        // calculate the rewards per share
        uint256 totalSupply = this.totalRewardSupplyBasis();

        if (totalSupply != 0) {
            totalRewardForDelta = timeDelta.mulDivDown(rewardPerSecond * rewardExpScale, totalSupply);
        } else {
            totalRewardForDelta = timeDelta * rewardPerSecond;
        }
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

            // make sure we don't reward over the end timestamp
            if (endBoundTimestamp > endTimestamp) {
                endBoundTimestamp = endTimestamp;
            }

            // if we havn't started yet
            if (lastRewardTimestamp == 0) {
                lastRewardTimestamp = startTimestamp;
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

            // if the user reduced their share
            if(user.shares != 0 && user.shares > shares) {
                // the user has earned rewards
                uint256 earnedRewards = (rewardsPerShare * (user.shares - shares)) / rewardExpScale;

                // add the earned rewards to the owed rewards
                user.owedRewards += earnedRewards;
            }

            // if the user increased their shares
            if(user.shares != 0 && user.shares < shares) {
                // the user has earned rewards
                uint256 earnedRewards = (rewardsPerShare * user.shares) / rewardExpScale;

                // reset their reward debt
                user.rewardDistributed = rewardsPerShare * shares;

                // add the earned rewards to the owed rewards
                user.owedRewards += earnedRewards;
            }

            // update the shares
            user.shares = shares;
        }
    }

    /// @notice return the pending rewards
    /// @param account the account to check
    function getPendingRewards(address account) external virtual updateReward(msg.sender) returns (uint256) {
        // check the user info
        UserInfo storage user = userInfo[account];

        // the current reward per share minus the reward debt
        uint256 owed = user.shares.mulDivDown(rewardsPerShare, rewardExpScale) - (user.rewardDistributed/rewardExpScale);

        // return the owned shares
        return owed + user.owedRewards;
    }

    /// @notice allows an account to claim the rewards
    /// @param recipient the recipient of the rewards
    function claimRewards(address recipient) external virtual {
        // the user info
        UserInfo storage user = userInfo[msg.sender];

        // check the user info
        uint256 pendingRewards = this.getPendingRewards(msg.sender);        

        // reset the zeroing
        user.rewardDistributed = user.shares * rewardsPerShare;

        // update the owed rewards
        user.owedRewards == 0;
        
        // if we round up, cap it at max rewards
        if (pendingRewards + totalRewardsPaid > totalRewards) {
            // if we round up 
            pendingRewards = totalRewards - totalRewardsPaid;
        }

        // update the total paid out
        totalRewardsPaid += pendingRewards;

        // transfer the rewards
        rewardToken.safeTransfer(recipient, pendingRewards);
    }

    // ---- ADMIN FUNCTIONS -----
    /// @notice change the start date if it hasn't started yet
    /// @param _startTimestamp the new start timestamp
    function setStartTimestamp(uint256 _startTimestamp) external onlyOwner {
        // make sure we haven't started yet
        require(block.timestamp < startTimestamp, "Rewards already started");

        // set the new start timestamp
        startTimestamp = _startTimestamp;

        // update the rewards per second
        rewardPerSecond = totalRewards / (endTimestamp - _startTimestamp);
    }

    /// @notice change the end date if it hasn't started yet
    /// @param _endTimestamp the new end timestamp
    function setEndTimestamp(uint256 _endTimestamp) external onlyOwner {
        // make sure we haven't started yet
        require(block.timestamp < startTimestamp, "Rewards already started");

        // set the new end timestamp
        endTimestamp = _endTimestamp;

        // update the rewards per second
        rewardPerSecond = totalRewards / (_endTimestamp - startTimestamp);
    }
}