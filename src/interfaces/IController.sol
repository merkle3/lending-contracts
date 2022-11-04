// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

interface IController {
    function platformFee() external returns(uint);

    // can user borrow this amount of value
    function isHealthy(address account) external returns (bool);

    // sell assets if the borrow is not solvant
    function buyAssets(address account, address[] calldata markets, uint256[] calldata tokenId) external returns (bool);
}