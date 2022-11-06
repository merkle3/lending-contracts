// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {ERC4626} from '../generics/ERC4626.sol';
import {IController} from '../interfaces/IController.sol';

// a token market is a pool of tokens that can be borrowed
// with the controller's permission
abstract contract IDebtMarket {
    // the controller
    IController public controller;

    modifier onlyController {
        require(msg.sender == address(controller), "ONLY_CONTROLLER");
        _;
    }

    // read the total of borrows for a user
    function getDebtBalanceUsd(address borrower) virtual external returns (uint256) {}

    // get the collateral value of a user
    function getCollateralUsd(address borrower) virtual external view returns (uint256) {}

    // a function to liquidate assets, that can only be called by the controller
    function liquidate(address borrower, address liquidator, bytes memory data) virtual external onlyController {}
}