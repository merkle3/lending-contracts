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
        mockAsset = new MockAsset();

        tokenMarket = new MToken(
            address(controller),
            address(mockToken),
            address(mockOracle),
            address(interestModel),
            1e18);

        controller.addAssetClass(address(mockAsset));
        controller.addDebtMarket(address(tokenMarket));

        mockOracle.updateAnswer(1e8);
    }

    function testSetup() public {
        assertEq(controller.totalDebtMarkets(), 1);
        assertEq(controller.totalAssetClasses(), 1);
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