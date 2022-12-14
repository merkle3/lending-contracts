// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;

import "forge-std/console.sol";
import {FixedPointMathLib} from '../src/libraries/FixedPointMathLib.sol';
import "forge-std/Test.sol";
import "../src/markets/MToken.sol";
import "../src/Controller.sol";
import "../src/interest/BaseInterestModel.sol";
import "./Constant.sol";
import "./mocks/MockV3Aggregator.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockAsset.sol";

contract InterestTest is Test {
    MToken public tokenMarket;
    MockAsset public mockAsset;
    Controller public controller;
    BaseInterestModel public interestModel;
    MockERC20 public mockToken;
    MockV3Aggregator public mockOracle;

    using FixedPointMathLib for uint256;

    function setUp() public {
        controller = new Controller();
        interestModel = new BaseInterestModel();
        mockToken = new MockERC20("MockUSDC", "mockUSDC");
        mockOracle = new MockV3Aggregator(8, 1e8);
        mockAsset = new MockAsset(address(controller));

        tokenMarket = new MToken(
            address(controller),
            address(mockToken),
            address(mockOracle),
            address(interestModel),
            1e18);

        controller.addDebtMarket(address(mockAsset));
        controller.addDebtMarket(address(tokenMarket));

        // fill the vault
        mockToken.mint(address(1), 10_000 * Constant.ONE);

        vm.prank(address(1));
        mockToken.approve(address(tokenMarket), 10_000 * Constant.ONE);

        vm.prank(address(1));
        tokenMarket.deposit(10_000 * Constant.ONE, address(1));

        // update the answer of aggregator
        mockOracle.updateAnswer(1e8);
    }

    function testInterestAccrual(uint amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 10_000);

        // borrow some funds
        mockAsset.setAmountUsd(address(2), 20_000);

        vm.prank(address(2));
        tokenMarket.borrow(amount * Constant.ONE, address(2));

        // go 100s in time
        vm.warp(block.timestamp + 100);

        // make sure the total borrow has increased
        assertGt(tokenMarket.getBorrowBalance(address(2)), amount * Constant.ONE);
        assertGt(tokenMarket.totalBorrows(), amount * Constant.ONE);
    }

    function testZeroInterest(uint amount) public {
        // make sure the best interest model returns zero
        assertEq(interestModel.getInterestRate(amount, 0), 0);
    }

    function testMaxApy(uint amount) public {
        // make sure it's les than 1 trillion
        vm.assume(amount < 1e12 * Constant.ONE);

        // and more than 0
        vm.assume(amount > 0);

        // make sure the best interest model returns the max apy
        assertEq(interestModel.getInterestRate(0, amount), 7_000);
    }

    function testTargetUtilization() public {
        assertEq(interestModel.getInterestRate(1_500, 8_500), 1_000);
    }

    function testBelowTargetUtilization() public {
        assertLt(interestModel.getInterestRate(2_500, 7_500), 1_000);
    }

    function testAboveTargetUtilization() public {
        assertGt(interestModel.getInterestRate(1_000, 9_000), 1_000);
    }
}
