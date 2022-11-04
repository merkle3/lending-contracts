// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;

import "forge-std/Test.sol";
import "../src/markets/MToken.sol";
import "../src/Controller.sol";
import "../src/interest/BaseInterestModel.sol";
import "../src/interfaces/AggregatorV3Interface.sol";
import "./Constant.sol";
import "./mocks/MockV3Aggregator.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockAsset.sol";

contract MTokenTest is Test {
    MToken public tokenMarket;
    Controller public controller;
    BaseInterestModel public interestModel;
    MockERC20 public mockToken;
    MockV3Aggregator public mockOracle;
    MockAsset public mockAsset;

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
}
