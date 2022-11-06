// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "forge-std/Script.sol";

import {Controller} from '../src/Controller.sol';
import {MToken} from '../src/markets/MToken.sol';
import {UniswapV3} from '../src/assets/UniswapV3.sol';
import {BaseInterestModel} from '../src/interest/BaseInterestModel.sol';

// deploy merkle on ethereum
contract DeployEth is Script {
    // the usdc address
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // the usdc oracle address
    address public constant USDC_ORACLE = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // the eth oracle address
    address public constant ETH_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // wrapped eth
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // dai
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // dai oracle
    address public constant DAI_ORACLE = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

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
        uniswapAssets.setOracle(DAI, DAI_ORACLE); // DAI

        // set the token scales
        uniswapAssets.setScaleFactor(WETH, 1); // ETH
        uniswapAssets.setScaleFactor(DAI, 1); // DAI
        uniswapAssets.setScaleFactor(USDC, 1e12); // USDC, 8 decimals scaled to 18

        // list of pools to activate
        address[] memory pools = new address[](4);

        // USDC-ETH 0.05%
        pools[0] = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

        // USDC-ETH 0.3%
        pools[1] = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;

        // DAI-USDC 0.01%
        pools[2] = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;

        // DAI-USDC 0.05%
        pools[3] = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;

        // activate pools
        uniswapAssets.activatePools(pools);

        // 4. Add the markets to the controller
        controller.addDebtMarket(address(uniswapAssets), 8_000);
        controller.addDebtMarket(address(usdcVault), 8_000);

        vm.stopBroadcast();
    }
}
