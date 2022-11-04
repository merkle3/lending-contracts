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

    function testExitHalfway(uint256 amount) public {
        // we set contrains on the amount of supply to test
        // the accuracy of the system
        vm.assume(amount > 0);
        // max 1 trillion units
        vm.assume(amount < 1_000_000_000_000 * Constant.ONE);

        rewarder.setAccountSupply(address(0), amount, amount);
        rewarder.setAccountSupply(address(1), amount, amount*2);

        // warp a half
        vm.warp(block.timestamp + 3600/2);

        rewarder.setAccountSupply(address(1), 0, amount);

        // warp a half
        vm.warp(block.timestamp + 3600/2);

        // 270,000 or 75% of the rewards
        assertApproxEqAbs(rewarder.getPendingRewards(address(0)), 360_000 / 4 * 3 * Constant.ONE, 10_000);
        // address should have 90,000, or 25% of the rewards
        assertApproxEqAbs(rewarder.getPendingRewards(address(1)), 360_000 / 4 * Constant.ONE, 10_000);
    }

    // test if a user joins the rewards, and exists before the rewards are claimed
    function testJoinAndExit(uint256 amount) public {
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
        vm.warp(block.timestamp + 3600/2);

        rewarder.setAccountSupply(address(1), 0, amount);

        // warp a quarter
        vm.warp(block.timestamp + 3600/4);

        //      25%            50%             25%
        // | -------- | ----------------- | -------- |
        //    addr1        addr1/addr2       addr1

        // 270,000 or 75% of the rewards
        assertApproxEqAbs(rewarder.getPendingRewards(address(0)), 360_000 / 4 * 3 * Constant.ONE, 10_000);
        // address should have 90,000, or 25% of the rewards
        assertApproxEqAbs(rewarder.getPendingRewards(address(1)), 360_000 / 4 * Constant.ONE, 10_000);
    }

    function testReinforcePosition(uint256 amount) public {
        // we set contrains on the amount of supply to test
        // the accuracy of the system
        vm.assume(amount > 0);
        // max 1 trillion units
        vm.assume(amount < 1_000_000_000_000 * Constant.ONE);

        rewarder.setAccountSupply(address(0), amount, amount);
        rewarder.setAccountSupply(address(1), amount, amount*2);

        // warp a quarter
        vm.warp(block.timestamp + 3600/2);

        rewarder.setAccountSupply(address(1), amount*2, amount*3);
        rewarder.setAccountSupply(address(0), amount*2, amount*4);

        // warp a quarter
        vm.warp(block.timestamp + 3600/2);

        //      50%                     50%             
        // | --------------- | ----------------- | 
        //    addr1/addr2        addr1*2/addr2*2    

        // they should have 50% each
        assertApproxEqAbs(rewarder.getPendingRewards(address(0)), 360_000 / 2 * Constant.ONE, 10_000);
        assertApproxEqAbs(rewarder.getPendingRewards(address(1)), 360_000 / 2 * Constant.ONE, 10_000);
    }

    function testRewardChanging(uint256 amount) public {
        // we set contrains on the amount of supply to test
        // the accuracy of the system
        vm.assume(amount > 0);
        // max 1 trillion units
        vm.assume(amount < 1_000_000_000_000 * Constant.ONE);

        rewarder.setAccountSupply(address(0), amount*2, amount*2);
        rewarder.setAccountSupply(address(1), amount*2, amount*4);

        // warp a half
        vm.warp(block.timestamp + 3600/2);

        rewarder.setAccountSupply(address(0), amount*1, amount*3);
        rewarder.setAccountSupply(address(1), amount*3, amount*4);

        // warp a half
        vm.warp(block.timestamp + 3600/2);

        //      50%                             50%             
        // | ----------------------- | ------------------------ | 
        //    addr0(50%)/addr1(50%)        addr0(25%)/addr1(75%)

        // they should have 50% each
        assertApproxEqAbs(rewarder.getPendingRewards(address(0)), 360_000 / 8 * 3 * Constant.ONE, 10_000);
        assertApproxEqAbs(rewarder.getPendingRewards(address(1)), 360_000 / 8 * 5 * Constant.ONE, 10_000);
    }
} 