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

contract BorrowTest is Test {
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
        mockAsset = new MockAsset();

        tokenMarket = new MToken(
            address(controller),
            address(mockToken),
            address(mockOracle),
            address(interestModel),
            1e18);

        controller.addAssetClass(address(mockAsset));
        controller.addMarket(address(tokenMarket));

        // fill the vault
        mockToken.mint(address(1), 10_000 * Constant.ONE);

        vm.prank(address(1));
        mockToken.approve(address(tokenMarket), 10_000 * Constant.ONE);

        vm.prank(address(1));
        tokenMarket.deposit(10_000 * Constant.ONE, address(1));

        // update the answer of aggregator
        mockOracle.updateAnswer(1e8);
    }

    function testBorrowWithoutCollateral(uint amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 10_000 * Constant.ONE);

        vm.expectRevert(bytes("NOT_HEALTHY"));

        tokenMarket.borrow(amount, msg.sender);
    }

    function testBorrowMoreThanReserves(uint amount) public {
        vm.assume(amount > 10_000 * Constant.ONE);

        vm.expectRevert(bytes("NO_RESERVES"));

        tokenMarket.borrow(amount, msg.sender);
    }

    function testBorrowToZeroAddress() public {
        vm.expectRevert(bytes("INVALID_RECEIVER"));

        tokenMarket.borrow(1 * Constant.ONE, address(0));
    }

    function testBorrow(uint amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 10_000);

        // provider the collateral
        mockAsset.setAmountUsd(amount);

        // try to borrow less than 80% of the collateral
        uint borrowAmount = amount.mulDivDown(8_000, 10_000);

        tokenMarket.borrow(borrowAmount * Constant.ONE, msg.sender);

        // check that we received the funds
        assertEq(mockToken.balanceOf(msg.sender), borrowAmount * Constant.ONE);
    }

    function testBorrowTooMuch(uint amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 10_000);

        mockAsset.setAmountUsd(amount);

        uint borrowAmount = amount.mulDivDown(8_000, 10_000) + 1;

        vm.expectRevert(bytes("NOT_HEALTHY"));

        // try to borrow more than collateral
        tokenMarket.borrow(borrowAmount * Constant.ONE, msg.sender);
    }
}
