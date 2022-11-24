// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "forge-std/Script.sol";

import {Controller} from '../src/Controller.sol';
import {MToken} from '../src/markets/MToken.sol';
import {UniswapV3} from '../src/assets/UniswapV3.sol';
import {BaseInterestModel} from '../src/interest/BaseInterestModel.sol';
import {MerkleToken} from '../src/token/Merkle.sol';

// deploy merkle on ethereum
contract DeployPolygon is Script {
    // the usdc address
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    // the usdc oracle address
    address public constant USDC_ORACLE = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;

    // the eth oracle address
    address public constant ETH_ORACLE = 0xF9680D99D6C9589e2a93a78A04A279e509205945;

    // wrapped eth
    address public constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;

    // matic
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    // matic oracle
    address public constant WMATIC_ORACLE = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

    // reward amount
    uint256 public constant REWARD_AMOUNT = 5000000000000000000000000;

    function run() external {
        address HARDWARE_WALLET = vm.envAddress("HARDWARE_WALLET");
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
        uniswapAssets.setFeeCollector(HARDWARE_WALLET);

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
        pools[0] = 0x45dDa9cb7c25131DF268515131f647d726f50608;

        // USDC-MATIC 0.05%
        pools[1] = 0xA374094527e1673A86dE625aa59517c5dE346d32;

        // MATIC-WETH 0.3%
        pools[2] = 0x167384319B41F7094e62f7506409Eb38079AbfF8;

        // activate pools
        uniswapAssets.activatePools(pools);

        // 4. Add the markets to the controller
        controller.addDebtMarket(address(uniswapAssets));
        controller.addDebtMarket(address(usdcVault));

        // 5. create merkle token
        MerkleToken mkl = new MerkleToken(HARDWARE_WALLET);

        // mint to vault
        mkl.setMintAllowance(vm.envAddress("DEPLOYER"), REWARD_AMOUNT);
        mkl.mint(address(usdcVault), REWARD_AMOUNT);

        // 6. transfer ownership to hardware wallet
        controller.transferOwnership(HARDWARE_WALLET);
        uniswapAssets.transferOwnership(HARDWARE_WALLET);
        usdcVault.transferOwnership(HARDWARE_WALLET);
        mkl.transferOwnership(HARDWARE_WALLET);

        vm.stopBroadcast();
    }
}
