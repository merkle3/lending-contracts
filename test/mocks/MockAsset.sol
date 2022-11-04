// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "forge-std/console.sol";
import '../../src/interfaces/IAssetClass.sol';

// used for testing
contract MockAsset is IAssetClass {
    mapping(address => uint256) amountUsd;

    // set the test amount
    function setAmountUsd(address account, uint256 _amountUsd) public {
        amountUsd[account] = _amountUsd;
    }

    // get the total collateral with all assets
    function getTotalCollateralUsd(address borrower) override virtual public view returns (uint256) {
        return amountUsd[borrower] * 1e8;
    }

    function transferAsset(address from, address to, uint256 tokenId) override virtual public onlyController {
        
    }
}
