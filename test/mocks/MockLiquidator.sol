// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;

import {IMerkleLiquidator} from '../../src/interfaces/IMerkleLiquidator.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockLiquidator is IMerkleLiquidator {
    address market;
    ERC20 token;
    uint256 amount;

    // set the payback amount
    function setPaybackAmount(uint256 _amount) external {
        amount = _amount;
    }

    // set the market to pay back
    function setMarket(address _market) external {
        market = _market;
    }

    // set the token
    function setToken(ERC20 _token) external {
        token = _token;
    }

    // repay the market
    function onMerkleLiquidation(address /*account*/, bytes memory /*callback*/) external override returns (bytes4) {
        // pay back the market
        token.transfer(market, amount);

        // return the selector
        return this.onMerkleLiquidation.selector;
    }
}