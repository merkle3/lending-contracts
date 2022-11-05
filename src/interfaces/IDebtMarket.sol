// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {ERC4626} from '../generics/ERC4626.sol';

// a token market is a pool of tokens that can be borrowed
// with the controller's permission
abstract contract IDebtMarket is ERC4626 {
    // read the total of borrows for a user
    function getDebtBalanceUsd(address borrower) virtual external returns (uint256) {}
}