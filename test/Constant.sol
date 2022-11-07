// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

library Constant {
    uint constant ONE = 1e18;

    // the usdc address
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // the usdc oracle address
    address public constant USDC_ORACLE = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    // the eth oracle address
    address public constant ETH_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // wrapped eth
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // usdc-weth
    address public constant WETH_USDC_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    // usdc-dai
    address public constant DAI_USDC_POOL = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;

    // dai
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // dai oracle
    address public constant DAI_ORACLE = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    // big usdc balance owner
    address public constant BIG_USDC_BALANCE_OWNER = 0x55FE002aefF02F77364de339a1292923A15844B8;
}