// SPDX-License-Identifier: UNLICENSED
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

    function testSetup() public {
        assertEq(tokenMarket.totalAssets(), 0);
        assertEq(tokenMarket.getBorrowRate(), Constant.ONE);
    }

    function testAddMarket() public {
        controller.addMarket(address(tokenMarket));

        assertEq(controller.totalTokenMarkets(), 1);
        assertEq(controller.totalAssetClasses(), 0);
    }

    function testAddFakeAssetClass() public {
        IAssetClass asset = new MockAsset();
        controller.addAssetClass(address(asset));

        assertEq(controller.totalTokenMarkets(), 0);
        assertEq(controller.totalAssetClasses(), 1);
    }

    function depositUsdc() public {
        usdc.mint(msg.sender, 1000 * Constant.ONE);
        usdc.approve(address(tokenMarket), 1000 * Constant.ONE);

        tokenMarket.deposit(1000 * Constant.ONE, msg.sender);

        // make we have received the shares
        assertEq(tokenMarket.balanceOf(msg.sender), 1000 * Constant.ONE);
    }

    function depositUsdcTwice(address someoneElse, uint256 amount) public {
        vm.assume(someoneElse != msg.sender);

        usdc.mint(someoneElse, amount * Constant.ONE);
        usdc.mint(msg.sender, 1000 * Constant.ONE);

        usdc.approve(address(tokenMarket), 1000 * Constant.ONE);

        tokenMarket.deposit(1000 * Constant.ONE, msg.sender);

        vm.prank(someoneElse);

        usdc.approve(address(tokenMarket), amount * Constant.ONE);

        // make sure shares we minted have received the shares
        assertEq(tokenMarket.balanceOf(someoneElse), amount * Constant.ONE);
        assertEq(tokenMarket.totalAssets(), 1500 * Constant.ONE);
    }

    function withdrawUsdcTest(uint256 amount) public {
        usdc.mint(msg.sender, amount * Constant.ONE);
        usdc.approve(address(tokenMarket), amount * Constant.ONE);

        tokenMarket.deposit(amount * Constant.ONE, msg.sender);

        tokenMarket.withdraw(amount * Constant.ONE, msg.sender, msg.sender);

        // make we have received the shares
        assertEq(usdc.balanceOf(msg.sender), amount * Constant.ONE);
        assertEq(tokenMarket.totalAssets(), amount * Constant.ONE);
    }
}
