// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// the merkle token is a enhanced token that allows for the 
// owner the mint and burn tokens at will
contract MerkleToken is ERC20, Ownable {
    constructor() ERC20("Merkle", "MKL") {
        // transfer ownership
        transferOwnership(msg.sender);
    }
}