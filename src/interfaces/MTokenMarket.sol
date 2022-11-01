// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import {ERC4626} from '../generics/ERC4626.sol';

// a token market is a pool of tokens that can be borrowed
// with the controller's permission
abstract contract MTokenMarket is ERC4626 {
    // we need a borrow function
    function borrow(uint256 amount, address receiver) virtual external {}

    // we need a repay function
    function repay(address account, uint256 amount) virtual external {}

    // read the total of borrows for a user
    function getBorrowBalanceUsd(address borrower) virtual external returns (uint256) {}
}