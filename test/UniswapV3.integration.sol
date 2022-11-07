// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;

// uniswapv3 needs to be tested in a integration environment
import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/Controller.sol";
import "./Constant.sol";
import "../src/assets/UniswapV3.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract UniswapV3Integration is Test {
    Controller public controller;
    UniswapV3 public uniswapV3;

    function setUp() public {
        controller = new Controller();

        uniswapV3 = new UniswapV3(address(controller));

        // add oracle for usdc
        uniswapV3.setOracle(Constant.USDC, Constant.USDC_ORACLE);

        // add oracle for weth
        uniswapV3.setOracle(Constant.WETH, Constant.ETH_ORACLE);

        // add scale for usdc
        uniswapV3.setScaleFactor(Constant.USDC, 1e12);
        uniswapV3.setScaleFactor(Constant.WETH, 1e12);

        address[] memory pools = new address[](1);

        pools[0] = Constant.WETH_USDC_POOL;

        uniswapV3.activatePools(pools);

        assertEq(uniswapV3.activatedPools(Constant.WETH_USDC_POOL), true);  

        controller.addDebtMarket(address(uniswapV3), 8_000);

        // impersonate the big usdc holder and mint a uniswap v3
        // position

        // 1. we need to get some weth
        vm.prank(Constant.BIG_ETH_BALANCE_OWNER);
        // send the eth to the wrapped eth contract
        ERC20(Constant.WETH).transfer(Constant.BIG_USDC_BALANCE_OWNER, 100 * Constant.ONE);

        // log balance
        console.log("WETH balance", ERC20(Constant.WETH).balanceOf(Constant.BIG_USDC_BALANCE_OWNER));
    }

    function testAddPool() public {
        address[] memory pools = new address[](1);

        pools[0] = Constant.DAI_USDC_POOL;

        vm.expectRevert(bytes("MISSING_ORACLE_TOKEN0"));
        uniswapV3.activatePools(pools);

        // should fail after the oracle is added
        uniswapV3.setOracle(Constant.DAI, Constant.DAI_ORACLE);

        vm.expectRevert(bytes("MISSING_SCALE_TOKEN0"));
        uniswapV3.activatePools(pools);

        // should be ok after we set the scale
        uniswapV3.setScaleFactor(Constant.DAI, 1);

        uniswapV3.activatePools(pools);

        assertEq(uniswapV3.activatedPools(Constant.DAI_USDC_POOL), true);
    }

    function testPausePool() public {
        uniswapV3.pausePool(Constant.WETH_USDC_POOL);

        assertEq(uniswapV3.activatedPools(Constant.WETH_USDC_POOL), false);
    }

    function testPausePoolShouldFail() public {
        // if we try to pause a pool that is not actived
        // it should fail
        vm.expectRevert(bytes("POOL_NOT_ACTIVE"));
        uniswapV3.pausePool(Constant.DAI_USDC_POOL);
    }
}