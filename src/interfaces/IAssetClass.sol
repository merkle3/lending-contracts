// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import '../interfaces/IController.sol';

// an asset class is a wrapped version of a 721 collection
// wrapped asset classes are non-transferable
abstract contract IAssetClass {
    // the controller
    IController public controller;

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

    modifier onlyController {
        require(msg.sender == address(controller), "ONLY_CONTROLLER");
        _;
    }

    // get the total collateral with all assets
    function getTotalCollateralUsd(address borrower) virtual public view returns (uint256) {}

    // transfer assets
    function transferAsset(address from, address to, uint256 tokenId) onlyController virtual public {}
}