// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;

import "forge-std/Test.sol";
import "../../src/rewards/Rewards.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockRewarder is Rewards {
    uint256 public totalSupply;
    mapping(address => uint256) public supplyForAccount;

    constructor(ERC20 token, uint256 start, uint256 total, uint256 duration) Rewards(token, start, total, duration) {
        totalSupply = 0;
    }

    function setAccountSupply(address account, uint256 _supply, uint256 total) updateReward(account) public {
        supplyForAccount[account] = _supply;
        totalSupply = total;
    }

    function rewardSupplyBasis(address account) external override view returns (uint256) {
        return supplyForAccount[account];
    }

    function totalRewardSupplyBasis() external override view returns (uint256) {
        return totalSupply;
    }

    function update(address addr) external updateReward(addr) {
    }
}