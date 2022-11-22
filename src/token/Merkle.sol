// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC3156FlashLender} from '../interfaces/IERC3156FlashLender.sol';
import {IERC3156FlashBorrower} from '../interfaces/IERC3156FlashBorrower.sol';

// the merkle token is a enhanced token that allows for the 
// owner the mint and burn tokens at will
contract MerkleToken is ERC20, Ownable, IERC3156FlashLender {
    // minting allowances
    mapping(address => uint256) public mintAllowances;

    // fee recipient
    address public feeRecipient;

    // flash loan fee
    uint256 public flashLoanFee;

    // mint event
    event Mint(address indexed minter, address indexed to, uint256 amount);
    
    // mint allowance event
    event MintAllowance(address indexed minter, uint256 amount);

    // flash loan fee change
    event FlashLoanFee(uint256 amount);

    // flash loan 
    event FlashLoan(address indexed receiver, uint256 amount, uint256 fee);

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

    /// ---- FLASH MINT -----------

    // ------- Flash Loan provider (ERC3156) --------

    /// @notice The amount of currency available to be lent.
    /// @param token The loan currency.
    /// @return The amount of `token` that can be borrowed.
    function maxFlashLoan(
        address token
    ) override external view returns (uint256) {
        if(token != address(this)) return 0;

        // return the maximum of uint256
        return type(uint256).max;
    }

    /// @notice The fee to be charged for a given loan.
    /// @param token The loan currency.
    /// @param amount The amount of tokens lent.
    /// @return The amount of `token` to be charged for the loan, on top of the returned principal.
    function flashFee(
        address token,
        uint256 amount
    ) override external view returns (uint256) {
        if(token != address(this)) return 0;

        // apply a 0.005% fee
        return amount * flashLoanFee / 100_000;
    }

    /// @notice Initiate a flash loan.
    /// @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
    /// @param token The loan currency.
    /// @param amount The amount of tokens lent.
    /// @param data Arbitrary data structure, intended to contain user-defined parameters.
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) override external returns (bool) {
        if(token != address(this)) revert("WRONG_TOKEN");

        // calculate the fee
        uint fee = amount * flashLoanFee / 100_000;

        // mint the tokens
        _mint(address(receiver), amount);

        // call the receiver
        receiver.onFlashLoan(msg.sender, token, amount, fee, data);

        // burn the tokens
        _burn(address(receiver), amount + fee);

        // send the fee
        _mint(feeRecipient, fee);

        // log the event
        emit FlashLoan(address(receiver), amount, fee);

        // return true
        return true;
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

    /// @dev set the floash loan fee
    /// @param fee the fee to set
    function setFlashLoanFee(uint256 fee) public onlyOwner {
        // set the fee
        flashLoanFee = fee;

        // log the event
        emit FlashLoanFee(fee);
    }
}