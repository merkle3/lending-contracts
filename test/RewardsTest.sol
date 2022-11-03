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
        rewarder.setAccountSupply(address(0), 0, 0);

        // lets warp
        vm.warp(block.timestamp + 3600);

        assertEq(rewarder.getPendingRewards(address(0)), 0);
    }

    function testFullRewards(uint amount) public {
        // we set contrains on the amount of supply to test
        // the accuracy of the system
        vm.assume(amount > 0);
        // max 1 trillion units
        vm.assume(amount < 1_000_000_000_000 * Constant.ONE);

        rewarder.setAccountSupply(address(0), amount, amount);

        // lets warp
        vm.warp(block.timestamp + 3600);

        assertApproxEqAbs(rewarder.getPendingRewards(address(0)), rewarder.totalRewards(), 10_000);
    }

    function testHalfHalfRewards(uint amount) public {
        // we set contrains on the amount of supply to test
        // the accuracy of the system
        vm.assume(amount > 0);
        // max 1 trillion units
        vm.assume(amount < 1_000_000_000_000 * Constant.ONE);

        rewarder.setAccountSupply(address(0), amount, amount);
        rewarder.setAccountSupply(address(1), amount, amount*2);

        // lets warp
        vm.warp(block.timestamp + 3600);

        assertApproxEqAbs(rewarder.getPendingRewards(address(0)), 360_000 / 2 * Constant.ONE, 10_000);
        assertApproxEqAbs(rewarder.getPendingRewards(address(1)), 360_000 / 2 * Constant.ONE, 10_000);
    }

    function testJoinhalfway(uint amount) public {
        // we set contrains on the amount of supply to test
        // the accuracy of the system
        vm.assume(amount > 0);
        // max 1 trillion units
        vm.assume(amount < 1_000_000_000_000 * Constant.ONE);

        rewarder.setAccountSupply(address(0), amount, amount);
        rewarder.update(address(0));

        // warp half
        vm.warp(block.timestamp + 1800);

        rewarder.setAccountSupply(address(1), amount, amount*2);

        // warp half
        vm.warp(block.timestamp + 1800);

        assertApproxEqAbs(rewarder.getPendingRewards(address(0)), 360_000 / 4 * 3 * Constant.ONE, 10_000);
        assertApproxEqAbs(rewarder.getPendingRewards(address(1)), 360_000 / 4 * 1 * Constant.ONE, 10_000);
    }

    // test if a user joins the rewards, and exists before the rewards are claimed
    function xtestJoinAndExit(uint amount) public {
        // we set contrains on the amount of supply to test
        // the accuracy of the system
        vm.assume(amount > 0);
        // max 1 trillion units
        vm.assume(amount < 1_000_000_000_000 * Constant.ONE);

        rewarder.setAccountSupply(address(0), amount, amount);

        // warp a quarter
        vm.warp(block.timestamp + 3600/4);

        rewarder.setAccountSupply(address(1), amount, amount*2);

        // warp a quarter
        vm.warp(block.timestamp + 3600/4);

        rewarder.setAccountSupply(address(1), 0, amount);

        // warp a half
        vm.warp(block.timestamp + 3600/2);

        assertApproxEqAbs(rewarder.getPendingRewards(address(0)), 360_000 / 8 * 7 * Constant.ONE, 10_000);
        // address 1 should have half a quarter
        assertApproxEqAbs(rewarder.getPendingRewards(address(1)), 360_000 / 8 * 1 * Constant.ONE, 10_000);
    }
} 