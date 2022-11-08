// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;
pragma experimental ABIEncoderV2;

// uniswapv3 needs to be tested in a integration environment
import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/Controller.sol";
import "./Constant.sol";
import "../src/assets/UniswapV3.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

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

        // 1. we need to get some weth
        vm.prank(Constant.BIG_ETH_BALANCE_OWNER);
        // send the eth to the wrapped eth contract
        Constant.WETH.call{value: 100 ether}(bytes(""));

        // send eth to the address 1
        vm.prank(Constant.BIG_ETH_BALANCE_OWNER);
        address(1).call{value: 10 ether}(bytes(""));

        // transfer to address(1)
        vm.prank(Constant.BIG_ETH_BALANCE_OWNER);
        ERC20(Constant.WETH).transfer(address(1), 100 ether);

        // transfer usdc to address(1)
        vm.prank(Constant.BIG_USDC_BALANCE_OWNER);
        ERC20(Constant.USDC).transfer(address(1), 100_000_000 * Constant.ONE_USDC);
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

    function testCreatePosition() public {
        // approve the uniswap v3 contract to spend our weth
        vm.prank(address(1));
        ERC20(Constant.WETH).approve(Constant.UNISWAP_V3_POSITION_MANAGER, 2000 * Constant.ONE);
        vm.prank(address(1));
        ERC20(Constant.USDC).approve(Constant.UNISWAP_V3_POSITION_MANAGER, 2000 * Constant.ONE);

        // get the slot 0 of the pool
        (, int24 poolTick, , , , , ) = IUniswapV3Pool(
            Constant.WETH_USDC_POOL
        ).slot0();

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: Constant.USDC, // token 0
            token1: Constant.WETH, // token 1
            fee: 500, // fee
            tickLower: poolTick-10, // min tick
            tickUpper: poolTick+10, // max tick
            amount0Desired: 1600 * Constant.ONE_USDC, // amount0Desired
            amount1Desired: 1 * Constant.ONE, // amount1Desired
            amount0Min: 0, // amount0Min
            amount1Min: 0, // amount1Min
            recipient: address(1), // recipient
            deadline: block.timestamp + 1000 // deadline
        });

        // let's create a position
        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = INonfungiblePositionManager(Constant.UNISWAP_V3_POSITION_MANAGER).mint(params);

        assertEq(tokenId, 1);
    }
}