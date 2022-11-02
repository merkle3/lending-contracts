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
    MockERC20 public usdc;
    AggregatorV3Interface public usdcOracle;

    function setUp() public {
        controller = new Controller();
        interestModel = new BaseInterestModel();
        usdc = new MockERC20("MockUSDC", "mockUSDC");
        usdcOracle = new MockV3Aggregator(8, 1e8);

        tokenMarket = new MToken(
            address(controller),
            address(usdc),
            address(usdcOracle),
            address(interestModel),
            1e6);
    }
}