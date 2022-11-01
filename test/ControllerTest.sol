// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.5.0;

import "forge-std/Test.sol";
import "../src/Controller.sol";

contract ControllerTest is Test {
    Controller public controller;

    function setUp() public {
        controller = new Controller();
    }

    function testSetup() public {
        assertEq(controller.totalTokenMarkets(), 0);
        assertEq(controller.totalAssetClasses(), 0);
        assertGt(controller.platformFee(), 0);
    }

    function testEmptyColletarls(address addr) public {
        assertEq(controller.getTotalBorrow(addr), 0);
        assertEq(controller.getTotalCollateral(addr), 0);
        assertEq(controller.isHealthy(addr), true);
    }

    function testEmptyRewards(address addr) public {
        assertEq(controller.getPendingRewards(addr), 0);
    }

    function testSetPlatformFee(uint256 fee) public {
        controller.setPlatformFee(fee);
        assertEq(controller.platformFee(), fee);
    }
}