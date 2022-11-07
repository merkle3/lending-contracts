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

contract RepayTest is Test {
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

        controller.addDebtMarket(address(mockAsset), 8_000);
        controller.addDebtMarket(address(tokenMarket), 8_000);

        // fill the vault
        mockToken.mint(address(1), 10_000 * Constant.ONE);

        vm.prank(address(1));
        mockToken.approve(address(tokenMarket), 10_000 * Constant.ONE);

        vm.prank(address(1));
        tokenMarket.deposit(10_000 * Constant.ONE, address(1));

        // update the answer of aggregator
        mockOracle.updateAnswer(1e8);
    }

    function testRepaySharesInFull(uint amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 10_000);

        // borrow some funds
        mockAsset.setAmountUsd(address(2), 20_000);

        vm.startPrank(address(2));
        tokenMarket.borrow(amount * Constant.ONE, address(2));

        // go 100s in time
        vm.warp(block.timestamp + 100);

        // repay in full
        mockToken.mint(address(2), amount * 10 * Constant.ONE);
        mockToken.approve(address(tokenMarket), amount * 10 * Constant.ONE);

        uint shares = tokenMarket.borrowed(address(2));

        // make sure the total borrow has increased
        tokenMarket.repayShares(address(2), shares);

        // make sure the total borrow is now zero
        assertEq(tokenMarket.borrowed(address(2)), 0);
        assertEq(tokenMarket.totalBorrows(), 0);
    }

    function testRepayUnderlyingAmount(uint amount) public {
        vm.assume(amount > 1_000);
        vm.assume(amount < 10_000);

        // borrow some funds
        mockAsset.setAmountUsd(address(2), 20_000);

        vm.prank(address(2));
        tokenMarket.borrow(amount * Constant.ONE, address(2));

        // repay just 1k
        mockToken.mint(address(2), 1_000 * Constant.ONE);

        vm.prank(address(2));
        mockToken.approve(address(tokenMarket), 1_000 * Constant.ONE);

        vm.prank(address(2));
        tokenMarket.repay(address(2), 1_000 * Constant.ONE);

        // make sure we still have the rest of the debt
        assertEq(tokenMarket.getBorrowBalance(address(2)), amount * Constant.ONE - 1_000 * Constant.ONE);
    }

    function testRepayTooMuchUnderlying(uint amount) public {
        vm.assume(amount > 1_000);
        vm.assume(amount < 10_000);

        // borrow some funds
        mockAsset.setAmountUsd(address(2), 20_000);

        vm.prank(address(2));
        tokenMarket.borrow(amount * Constant.ONE, address(2));

        // repay just 1k
        mockToken.mint(address(2), 1_000 * Constant.ONE);

        vm.prank(address(2));
        mockToken.approve(address(tokenMarket), 1_000 * Constant.ONE);

        vm.prank(address(2));
        vm.expectRevert(bytes("OVER_PAID"));
        tokenMarket.repay(address(2), 11_000 * Constant.ONE);

        // make sure we still have the debt
        assertEq(tokenMarket.getBorrowBalance(address(2)), amount * Constant.ONE);
    }

    function testRepayTooMuchShares(uint amount) public {
        vm.assume(amount > 1_000);
        vm.assume(amount < 10_000);

        // borrow some funds
        mockAsset.setAmountUsd(address(2), 20_000);

        vm.prank(address(2));
        tokenMarket.borrow(amount * Constant.ONE, address(2));

        // repay just 1k
        mockToken.mint(address(2), 1_000 * Constant.ONE);

        vm.prank(address(2));
        mockToken.approve(address(tokenMarket), 1_000 * Constant.ONE);

        vm.prank(address(2));
        vm.expectRevert(bytes("OVER_PAID"));
        tokenMarket.repayShares(address(2), 11_000 * Constant.ONE);

        // make sure we still have the debt
        assertEq(tokenMarket.getBorrowBalance(address(2)), amount * Constant.ONE);
    }

    function testRepayNoFunds(uint amount) public {
        vm.assume(amount > 1_000);
        vm.assume(amount < 10_000);

        // borrow some funds
        mockAsset.setAmountUsd(address(2), 20_000);

        vm.prank(address(2));
        // send the funds somewhere else so we don't have them
        tokenMarket.borrow(amount * Constant.ONE, address(3));

        vm.prank(address(2));
        mockToken.approve(address(tokenMarket), 1_000 * Constant.ONE);

        vm.prank(address(2));
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        tokenMarket.repay(address(2), 1 * Constant.ONE);

        vm.prank(address(2));
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        tokenMarket.repayShares(address(2), 1 * Constant.ONE);

        // make sure we still have the debt
        assertEq(tokenMarket.getBorrowBalance(address(2)), amount * Constant.ONE);
    }
    
    function testRepayOtherAccount(uint amount) public {
        vm.assume(amount > 1_000);
        vm.assume(amount < 10_000);

        // borrow some funds
        mockAsset.setAmountUsd(address(2), 20_000);

        vm.prank(address(2));
        tokenMarket.borrow(amount * Constant.ONE, address(4));

        // repay just 1k
        mockToken.mint(address(3), amount * Constant.ONE);

        vm.prank(address(3));
        mockToken.approve(address(tokenMarket), amount * Constant.ONE);

        vm.prank(address(3));
        tokenMarket.repay(address(2), amount * Constant.ONE);

        // make sure the debt is cleared
        assertEq(tokenMarket.getBorrowBalance(address(2)), 0);
    }
}
