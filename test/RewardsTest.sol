// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;

import "forge-std/Test.sol";
import "./Constant.sol";
import "./mocks/MockRewarder.sol";
import "./mocks/MockERC20.sol";
import "../src/rewards/Rewards.sol";

contract MTokenTest is Test {
    MockRewarder public rewarder;
    MockERC20 public token;

    function setUp() public {
        token = new MockERC20("Mock usdc", "mockUSDC");

        // 10 000 tokens over an hour
        rewarder = new MockRewarder(token, block.timestamp, 360_000 * Constant.ONE, 3600);

        // send tokens to the rewarder
        token.mint(address(rewarder), 360_000 * Constant.ONE);
    }

    function testSetup() public {
        assertEq(token.totalSupply(), 360_000 * Constant.ONE);
        assertEq(token.balanceOf(address(rewarder)), 360_000 * Constant.ONE);
    }

    function testRewardZero() public {
        rewarder.setSupply(0);

        rewarder.setAccountSupply(address(0), 0);

        rewarder.update(address(0));

        // lets warp
        vm.warp(block.timestamp + 3600);

        rewarder.update(address(0));

        assertEq(rewarder.getPendingRewards(address(0)), 0);
    }

    function testFullRewards() public {
        rewarder.setSupply(1);

        rewarder.setAccountSupply(address(0), 1);

        rewarder.update(address(0));

        // lets warp
        vm.warp(block.timestamp + 3600);

        rewarder.update(address(0));

        assertEq(rewarder.getPendingRewards(address(0)), 360_000 * Constant.ONE);
    }

    function testHalfHalfRewards() public {
        rewarder.setSupply(2);

        rewarder.setAccountSupply(address(0), 1);
        rewarder.setAccountSupply(address(1), 1);

        rewarder.update(address(0));
        rewarder.update(address(1));

        // lets warp
        vm.warp(block.timestamp + 3600);

        rewarder.update(address(0));
        rewarder.update(address(1));

        assertEq(rewarder.getPendingRewards(address(0)), 360_000 / 2 * Constant.ONE);
        assertEq(rewarder.getPendingRewards(address(1)), 360_000 / 2 * Constant.ONE);
    }

    function Joinhalfway() public {
        rewarder.setSupply(1);

        rewarder.setAccountSupply(address(0), 1);
        rewarder.update(address(0));

        // warp half
        vm.warp(block.timestamp + 1800);

        rewarder.setSupply(2);
        rewarder.setAccountSupply(address(1), 1);
        rewarder.update(address(1));

        // warp half
        vm.warp(block.timestamp + 1800);

        rewarder.update(address(0));
        rewarder.update(address(1));

        assertEq(rewarder.getPendingRewards(address(0)), 360_000 / 4 * 3 * Constant.ONE);
        assertEq(rewarder.getPendingRewards(address(1)), 360_000 / 4 * 1 * Constant.ONE);
    }
} 