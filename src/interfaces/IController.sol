// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

interface IController {
    function platformFee() external returns(uint);

    // can user borrow this amount of value
    function isHealthy(address account) external returns (bool);

    // sell assets if the borrow is not solvant
    function liquidate(address account, address[] calldata markets, bytes[] calldata datas, address liquidator, bytes memory data) external returns (bool);
}