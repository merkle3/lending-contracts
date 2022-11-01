// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

interface IMerkleCallback {
    // called when a token is minted
    function onMerkleMint(address caller, uint tokenId, address receiver, bytes memory callback) external returns (bytes4 retval);

    // called when a token is burned
    function onMerkleBurn(address caller, uint tokenId, bytes memory callback) external returns (bytes4 retval);
}