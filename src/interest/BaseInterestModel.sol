// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {IInterestModel} from './IInterestModel.sol';
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";

contract BaseInterestModel is IInterestModel {
    using FixedPointMathLib for uint256;

    uint constant public expScale = 1e18;

    uint constant public TARGET_APY = 1_000; // 10%

    uint constant public UTILIZATION_TARGET = 8_500; // add a multiplier after 85%

    uint constant public MAX_APY = 7_000; // 70% when 100% utilization

    // 10_000 = 1%
    function getInterestRate(uint cash, uint borrows) override virtual external view returns (uint) {
        if(borrows == 0) {
            return 0;
        }

        // 1. get the utilization rate
        uint utilization = borrows.mulDivUp(10_000, (cash + borrows));

        // 2. calculate the interest rate
        uint interestRate = 0;

        // 3. add a multiplier if utilization is high
        if (utilization > UTILIZATION_TARGET) {
            uint excess = utilization - UTILIZATION_TARGET;

            // if above utilization target, calculate where it is 
            // on the slope that tarts at TARGET_APY and ends at MAX_APY
            interestRate = TARGET_APY + (MAX_APY-TARGET_APY).mulDivUp(excess, 10_000 - UTILIZATION_TARGET);
        } else {
            // if it's under the utilzation target, calculate where it is
            // on the slope
            interestRate = TARGET_APY.mulDivUp(utilization, UTILIZATION_TARGET);
        }

        return interestRate;
    }
}