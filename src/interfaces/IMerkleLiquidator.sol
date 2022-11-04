// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

interface IMerkleLiquidator {
    // called when a token is minted
    function onMerkleLiquidation(address account, bytes memory callback) external returns (bytes4 retval);
}