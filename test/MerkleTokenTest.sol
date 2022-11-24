// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";

import {MerkleToken} from '../src/token/Merkle.sol';

contract MerkleTokenTest is Test {
    MerkleToken public token;

    function setUp() public {
        token = new MerkleToken();
        token.transferOwnership(address(2));
    }

    function testMint(address to, uint amount) public {
        vm.assume(amount > 0);
        vm.assume(to != address(0));

        vm.expectRevert(bytes("NOT_ENOUGH_ALLOWANCE"));

        token.mint(to, amount);
    }

    function testMintAllowance(address receiver, uint amount) public {
        vm.assume(amount > 0);
        vm.assume(receiver != address(0));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));

        vm.prank(address(3));
        token.setMintAllowance(receiver, amount);
    }

    function testMintAllowanceSuccess(address receiver, uint amount) public {
        vm.assume(amount > 0);
        vm.assume(receiver != address(0));

        vm.prank(address(2));
        token.setMintAllowance(receiver, amount);

        assertEq(token.mintAllowances(receiver), amount);
    }

    function testMintWithAllowance(address minter, address receiver, uint amount) public {
        vm.assume(amount > 0);
        vm.assume(minter != address(0));
        vm.assume(receiver != address(0));

        vm.prank(address(2));
        token.setMintAllowance(minter, amount);

        vm.prank(minter);
        token.mint(receiver, amount);

        // make sure the allowance is reduced
        assertEq(token.mintAllowances(minter), 0);

        // make sure tokens are received
        assertEq(token.balanceOf(receiver), amount);
    }

    function testMintMoreThanAllowed(address minter, address receiver, uint amount) public {
        vm.assume(amount > 0);
        // must be less than uint256 max - 1
        vm.assume(amount < type(uint256).max - 1);
        vm.assume(minter != address(0));
        vm.assume(receiver != address(0));

        vm.prank(address(2));
        token.setMintAllowance(minter, amount);

        vm.expectRevert(bytes("NOT_ENOUGH_ALLOWANCE"));

        vm.prank(minter);
        token.mint(receiver, amount + 1);
    }

    function testMintMultipleTimesFailure(address minter, address receiver, uint amount) public {
        vm.assume(amount > 0);
        vm.assume(minter != address(0));
        vm.assume(receiver != address(0));

        vm.prank(address(2));
        token.setMintAllowance(minter, amount);

        vm.prank(minter);
        token.mint(receiver, amount);

        vm.expectRevert(bytes("NOT_ENOUGH_ALLOWANCE"));

        vm.prank(minter);
        token.mint(receiver, 1);
    }

    function testMintMultipleTimesSuccess(address minter, address receiver, uint amount) public {
        vm.assume(amount > 2);
        vm.assume(minter != address(0));
        vm.assume(receiver != address(0));

        vm.prank(address(2));
        token.setMintAllowance(minter, amount);

        vm.prank(minter);
        token.mint(receiver, 1);

        vm.prank(minter);
        token.mint(receiver, 1);

        // make sure received got the tokens
        assertEq(token.balanceOf(receiver), 2);

        // make sure allowance is reduced
        assertEq(token.mintAllowances(minter), amount - 2);
    }
}