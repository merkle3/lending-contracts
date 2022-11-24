// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Lockable} from '../utils/Lockable.sol';

// the merkle token is a enhanced token that allows for the 
// owner the mint and burn tokens at will
contract MerkleToken is ERC20, Ownable {
    // minting allowances
    mapping(address => uint256) public mintAllowances;

    // mint event
    event Mint(address indexed minter, address indexed to, uint256 amount);
    
    // mint allowance event
    event MintAllowance(address indexed minter, uint256 amount);

    constructor() ERC20("Merkle", "MKL") {
        // transfer ownership
        transferOwnership(msg.sender);
    }

    /// @dev mint tokens
    /// @param to the account to mint to
    /// @param amount the amount to mint
    function mint(address to, uint256 amount) public {
        // check if the sender has enough allowance
        require(mintAllowances[msg.sender] >= amount, "NOT_ENOUGH_ALLOWANCE");

        // reduce the allowance
        mintAllowances[msg.sender] -= amount;

        // mint the tokens
        _mint(to, amount);

        // log the event
        emit Mint(msg.sender, to, amount);
    }

    /// ---- ADMIN FUNCTIONS ------
    /// @dev set a minting allowances
    /// @param account the account to set the allowance for
    /// @param amount the amount to set the allowance to
    function setMintAllowance(address account, uint256 amount) public onlyOwner {
        // set the allowance
        mintAllowances[account] = amount;

        // log the event
        emit MintAllowance(account, amount);
    }
}