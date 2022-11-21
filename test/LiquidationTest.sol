// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import "../src/markets/MToken.sol";
import "../src/Controller.sol";
import "../src/interest/BaseInterestModel.sol";
import "../src/interfaces/AggregatorV3Interface.sol";
import "./Constant.sol";
import "./mocks/MockV3Aggregator.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockLiquidator.sol";
import "./mocks/MockAsset.sol";

contract MTokenTest is Test {
    MToken public tokenMarket;
    Controller public controller;
    BaseInterestModel public interestModel;
    MockERC20 public mockToken;
    MockV3Aggregator public mockOracle;
    MockAsset public mockAsset;
    MockLiquidator public mockLiquidator;

    function setUp() public {
        controller = new Controller();
        interestModel = new BaseInterestModel();
        mockToken = new MockERC20("MockUSDC", "mockUSDC");
        mockOracle = new MockV3Aggregator(8, 1e8);
        mockAsset = new MockAsset(address(controller));
        mockLiquidator = new MockLiquidator();

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

        // set the liquidation token
        mockLiquidator.setToken(mockToken);
        // set the liquidation market
        mockLiquidator.setMarket(tokenMarket);
    }

    function testHealthyState(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < 8_000 * Constant.ONE);
        
        // make the fake asset worth 10k
        mockAsset.setAmountUsd(address(2), 10_000);

        // take a 8k loan on address(2)
        vm.prank(address(2));
        tokenMarket.borrow(amount, address(2));

        // make sure its unhealthy
        assertEq(controller.isHealthy(address(2)), true);

        // make sure liquidate reverts
        vm.expectRevert(bytes("CANNOT_LIQUIDATE"));

        address[] memory markets = new address[](0);
        bytes[] memory data = new bytes[](0);

        controller.liquidate(
            address(2), 
            markets, 
            data, 
            address(mockLiquidator), 
            bytes("")
        );
    }

    function testLiquidationState(uint256 amount) public {
        vm.assume(amount >= 5_000 * Constant.ONE);
        vm.assume(amount <= 8_000 * Constant.ONE);

        // make the fake asset worth 10k
        mockAsset.setAmountUsd(address(2), 10_000);

        // take a 8k loan on address(2)
        vm.prank(address(2));
        tokenMarket.borrow(amount, address(2));

        // make the fake asset worth 5k
        mockAsset.setAmountUsd(address(2), 5_000);

        // make sure its unhealthy
        assertEq(controller.isHealthy(address(2)), false);
    }

    function testPartialLiquidation() public {
        // borrow 8k token
        uint256 amount = 8_000 * Constant.ONE;

        // make the fake asset worth 10k
        mockAsset.setAmountUsd(address(2), 10_000);

        // take a 8k loan on address(2)
        vm.prank(address(2));
        tokenMarket.borrow(amount, address(2));

        // make the fake asset worth 5k
        mockAsset.setAmountUsd(address(2), 5_000);

        // make sure its unhealthy
        assertEq(controller.isHealthy(address(2)), false);

        // now we can liquidate
        
        // first, we need to give the liquidator some tokens
        mockToken.mint(address(mockLiquidator), 10_000 * Constant.ONE);
        // then we need to tell it to wipe the debt
        mockLiquidator.setPaybackAmount(address(2), amount/2);

        address[] memory markets = new address[](1);
        bytes[] memory data = new bytes[](1);

        markets[0] = address(mockAsset);

        // then we liquidate
        controller.liquidate(
            address(2), 
            markets, 
            data, 
            address(mockLiquidator), 
            bytes("")
        );

        // and we should have a healthy account
        assertEq(controller.isHealthy(address(2)), true);

        // make sure the debt is half
        assertEq(tokenMarket.getBorrowBalance(address(2)), amount/2);
    }
    
    function testFailedPartialLiquidation() public {
        // borrow 8k token
        uint256 amount = 8_000 * Constant.ONE;

        // make the fake asset worth 10k
        mockAsset.setAmountUsd(address(2), 10_000);

        // take a 8k loan on address(2)
        vm.prank(address(2));
        tokenMarket.borrow(amount, address(2));

        // make the fake asset worth 5k
        mockAsset.setAmountUsd(address(2), 5_000);

        // make sure its unhealthy
        assertEq(controller.isHealthy(address(2)), false);

        // now we can liquidate
        
        // first, we need to give the liquidator some tokens
        mockToken.mint(address(mockLiquidator), 10_000 * Constant.ONE);
        // then we need to tell it to wipe the debt
        mockLiquidator.setPaybackAmount(address(2), amount/2-1);

        address[] memory markets = new address[](1);
        bytes[] memory data = new bytes[](1);

        markets[0] = address(mockAsset);

        // then we liquidate
        controller.liquidate(
            address(2), 
            markets, 
            data, 
            address(mockLiquidator), 
            bytes("")
        );

        // make sure the account still has the same amount of debt
        assertEq(tokenMarket.getBorrowBalance(address(2)), amount);

        // and we should have a healthy account
        assertEq(controller.isHealthy(address(2)), false);
    }

    function testLiquidation(uint256 amount) public {
        vm.assume(amount >= 5_000 * Constant.ONE);
        vm.assume(amount <= 8_000 * Constant.ONE);

        // make the fake asset worth 10k
        mockAsset.setAmountUsd(address(2), 10_000);

        // take a 8k loan on address(2)
        vm.prank(address(2));
        tokenMarket.borrow(amount, address(2));

        // make the fake asset worth 5k
        mockAsset.setAmountUsd(address(2), 0);

        // make sure its unhealthy
        assertEq(controller.isHealthy(address(2)), false);

        // now we can liquidate
        
        // first, we need to give the liquidator some tokens
        mockToken.mint(address(mockLiquidator), 10_000 * Constant.ONE);
        // then we need to tell it to wipe the debt
        mockLiquidator.setPaybackAmount(address(2), amount);

        address[] memory markets = new address[](1);
        bytes[] memory data = new bytes[](1);

        markets[0] = address(mockAsset);

        // then we liquidate
        controller.liquidate(
            address(2), 
            markets, 
            data, 
            address(mockLiquidator), 
            bytes("")
        );

        // and we should have a healthy account
        assertEq(controller.isHealthy(address(2)), true);
    }

    function testFailedLiquidation(uint amount) public {
        vm.assume(amount >= 5_000 * Constant.ONE);
        vm.assume(amount <= 8_000 * Constant.ONE);

        // make the fake asset worth 10k
        mockAsset.setAmountUsd(address(2), 10_000);

        // take a 8k loan on address(2)
        vm.prank(address(2));
        tokenMarket.borrow(amount, address(2));

        // make the fake asset worth 0
        mockAsset.setAmountUsd(address(2), 0);

        // make sure its unhealthy
        assertEq(controller.isHealthy(address(2)), false);

        // now we can liquidate
        
        // first, we need to give the liquidator some tokens
        mockToken.mint(address(mockLiquidator), 10_000 * Constant.ONE);
        // then we need to tell it to wipe the debt
        mockLiquidator.setPaybackAmount(address(2), amount-1);

        address[] memory markets = new address[](1);
        bytes[] memory data = new bytes[](1);

        markets[0] = address(mockAsset);

        // then we liquidate
        controller.liquidate(
            address(2), 
            markets, 
            data, 
            address(mockLiquidator), 
            bytes("")
        );

        // make sure the account still has the same amount of debt
        assertEq(tokenMarket.getBorrowBalance(address(2)), amount);

        // and we should have a healthy account
        assertEq(controller.isHealthy(address(2)), false);
    }
}
