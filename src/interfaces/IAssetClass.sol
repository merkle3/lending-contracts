// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {IDebtMarket} from './IDebtMarket.sol';

// an asset class is a wrapped version of a 721 collection
// wrapped asset classes are non-transferable
abstract contract IAssetClass is IDebtMarket {
    // deposit event
    event Deposit(
        address indexed owner, 
        address indexed receiver, 
        uint256 tokenId
    );

    // withdraw event
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed origin,
        uint256 tokenId
    );

    // debt always returns 0
    function getDebtBalanceUsd(address /*borrower*/) virtual external override returns (uint256) {
        return 0;
    }
}