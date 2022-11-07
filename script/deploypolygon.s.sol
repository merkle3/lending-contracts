// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "forge-std/Script.sol";

import {Controller} from '../src/Controller.sol';
import {MToken} from '../src/markets/MToken.sol';
import {UniswapV3} from '../src/assets/UniswapV3.sol';
import {BaseInterestModel} from '../src/interest/BaseInterestModel.sol';

// deploy merkle on ethereum
contract DeployPolygon is Script {
    // the usdc address
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    // the usdc oracle address
    address public constant USDC_ORACLE = 0xfe4a8cc5b5b2366c1b58bea3858e81843581b2f7;

    // the eth oracle address
    address public constant ETH_ORACLE = 0xf9680d99d6c9589e2a93a78a04a279e509205945;

    // wrapped eth
    address public constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;

    // matic
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    // matic oracle
    address public constant WMATIC_ORACLE = 0xab594600376ec9fd91f8e885dadf0ce036862de0;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. deploy the controller
        Controller controller = new Controller();

        // 2. deploy and configure the USDC market
        // deploy an interest model
        BaseInterestModel interestModel = new BaseInterestModel();

        MToken usdcVault = new MToken(
            // the controller
            address(controller),
            // the usdc address
            USDC,
            // the oracle address
            USDC_ORACLE,
            // the interest model
            address(interestModel),
            // the usdc token decimals
            1e6
        );

        // 3. deploy and configure the uniswapv3 asset
        UniswapV3 uniswapAssets = new UniswapV3(address(controller));

        // set the oracles
        uniswapAssets.setOracle(WETH, ETH_ORACLE); // ETH
        uniswapAssets.setOracle(USDC, USDC_ORACLE); // USDC
        uniswapAssets.setOracle(WMATIC, WMATIC_ORACLE); // BTC

        // set the token scales
        uniswapAssets.setScaleFactor(WETH, 1); // ETH
        uniswapAssets.setScaleFactor(WMATIC, 1); // WMATIC
        uniswapAssets.setScaleFactor(USDC, 1e12); // USDC, 8 decimals scaled to 18

        // list of pools to activate
        address[] memory pools = new address[](3);

        // USDC-WETH 0.05%
        pools[0] = 0x45dda9cb7c25131df268515131f647d726f50608;

        // USDC-MATIC 0.05%
        pools[1] = 0xa374094527e1673a86de625aa59517c5de346d32;

        // MATIC-WETH 0.3%
        pools[2] = 0x167384319b41f7094e62f7506409eb38079abff8;

        // activate pools
        uniswapAssets.activatePools(pools);

        // 4. Add the markets to the controller
        controller.addDebtMarket(address(uniswapAssets), 8_000);
        controller.addDebtMarket(address(usdcVault), 8_000);

        vm.stopBroadcast();
    }
}
