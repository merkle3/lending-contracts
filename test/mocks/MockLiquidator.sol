// SPDX-License-Identifier: BUSL-1.1
pragma solidity >= 0.5.0;

import {IMerkleLiquidator} from '../../src/interfaces/IMerkleLiquidator.sol';
import {MToken} from '../../src/markets/MToken.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockLiquidator is IMerkleLiquidator {
    MToken market;
    ERC20 token;
    mapping(address => uint256) amount;

    // set the payback amount
    function setPaybackAmount(address account, uint256 _amount) external {
        amount[account] = _amount;
    }

    // set the market to pay back
    function setMarket(MToken _market) external {
        market = _market;
    }

    // set the token
    function setToken(ERC20 _token) external {
        token = _token;
    }

    // repay the market
    function onMerkleLiquidation(address account, bytes memory /*callback*/) external override returns (bytes4) {
        // authorize the market with token
        token.approve(address(market), amount[account]);

        // repay the debt
        market.repay(account, amount[account]);

        // return the selector
        return this.onMerkleLiquidation.selector;
    }
}