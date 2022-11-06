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

contract ControllerTest is Test {
    MToken public tokenMarket;
    MockAsset public mockAsset;
    Controller public controller;
    BaseInterestModel public interestModel;
    MockERC20 public mockToken;
    MockV3Aggregator public mockOracle;

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

        mockOracle.updateAnswer(1e8);
    }

    function testSetup() public {
        assertEq(controller.totalDebtMarkets(), 2);
        assertGt(controller.platformFee(), 0);
    }

    function testEmptyColletarls(address addr) public {
        assertEq(controller.getTotalBorrowUsd(addr), 0);
        assertEq(controller.getTotalCollateralUsd(addr), 0);
        assertEq(controller.isHealthy(addr), true);
    }

    function testSetPlatformFee(uint256 fee) public {
        controller.setPlatformFee(fee);
        assertEq(controller.platformFee(), fee);
    }

    event CollateralRateChanged(address indexed tokenMarket, uint256 rate);

    function testChangeCollateral() public {
        // set a collateral
        mockAsset.setAmountUsd(address(2), 10_000);

        // check that the default 80% is applied
        assertEq(controller.getTotalCollateralUsd(address(2)), 8_000 * 1e8);

        // expect the emittion
        vm.expectEmit(true, false, false, false);
        emit CollateralRateChanged(address(mockAsset), 4_000);

        // change the collateral usage of mock asset
        controller.setCollateralRate(address(mockAsset), 4_000);

        // make sure the new collateral is half
        assertEq(controller.getTotalCollateralUsd(address(2)), 4_000 * 1e8);
    }
}