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
            1e18);
    }

    function testAddDebtMarket() public {
        controller.addDebtMarket(address(tokenMarket), 8_000);

        assertEq(controller.totalDebtMarkets(), 1);
    }

    function testDepositUsdc() public {
        usdc.mint(address(1), 1000 * Constant.ONE);

        vm.prank(address(1));
        usdc.approve(address(tokenMarket), 1000 * Constant.ONE);

        vm.prank(address(1));
        tokenMarket.deposit(1000 * Constant.ONE, address(1));

        // make we have received the shares
        assertEq(tokenMarket.balanceOf(address(1)), 1000 * Constant.ONE);
    }

    function testDepositUsdcTwice(address someoneElse, uint256 amount) public {
        vm.assume(someoneElse != address(1));
        vm.assume(someoneElse != address(0));

        // deposit less than 1 trillion
        vm.assume(amount < 1_000_000_000_000);
        // and more than 0
        vm.assume(amount > 0);

        // if we deposit usdc
        usdc.mint(address(1), 1000 * Constant.ONE);

        vm.prank(address(1));
        usdc.approve(address(tokenMarket), 1000 * Constant.ONE);

        vm.prank(address(1));
        tokenMarket.deposit(1000 * Constant.ONE, address(1));

        // and someone else deposits
        usdc.mint(someoneElse, amount * Constant.ONE);

        vm.prank(someoneElse);
        usdc.approve(address(tokenMarket), amount * Constant.ONE);

        vm.prank(someoneElse);
        tokenMarket.deposit(amount * Constant.ONE, someoneElse);

        // make sure shares we minted have received the shares
        assertEq(tokenMarket.balanceOf(someoneElse), amount * Constant.ONE);
        assertEq(tokenMarket.balanceOf(address(1)), 1000 * Constant.ONE);
        assertEq(tokenMarket.totalAssets(), (amount + 1000) * Constant.ONE);
    }

    function testWithdrawUsdcTest(uint256 amount) public {
        // deposit less than 1 trillion
        vm.assume(amount < 1_000_000_000_000);
        // and more than 0
        vm.assume(amount > 0);

        usdc.mint(address(1), amount * Constant.ONE);

        vm.prank(address(1));
        usdc.approve(address(tokenMarket), amount * Constant.ONE);

        vm.prank(address(1));
        tokenMarket.deposit(amount * Constant.ONE, address(1));

        vm.prank(address(1));
        tokenMarket.withdraw(amount * Constant.ONE, address(1), address(1));

        // we have received the amount
        assertEq(usdc.balanceOf(address(1)), amount * Constant.ONE);
        // the market has no assets
        assertEq(tokenMarket.totalAssets(), 0);
    }
}
