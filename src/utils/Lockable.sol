// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

/**
 * @dev provides a utility to lock a contract for the whole transaction
 */
abstract contract Lockable {
    /// @dev a lock slot
    bool private locked;

    /// @dev lock the contract for the transaction
    modifier lock() {
        require(!locked, "Lockable: locked");
        locked = true;
        _;
        locked = false;
    }
}