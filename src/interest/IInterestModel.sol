// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

interface IInterestModel {
    /**
      * @notice Calculates the current borrow interest rate per year
      * @param cash The total amount of cash the market has
      * @param borrows The total amount of borrows the market has outstanding
      * @return The borrow rate per year (as a percentage)
      */
    function getBorrowRate(uint cash, uint borrows) external view returns (uint);
}