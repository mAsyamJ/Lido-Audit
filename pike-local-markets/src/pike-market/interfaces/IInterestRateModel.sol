// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IInterestRateModel {
    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     */
    function getUtilization(uint256 cash, uint256 borrows, uint256 reserves)
        external
        view
        returns (uint256);

    /**
     * @notice Calculates the current borrow rate per second
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow interest rate per second, scaled by 1e18
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves)
        external
        view
        returns (uint256);

    /**
     * @notice Calculates the current supply rate per second
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply interest rate per second, scaled by 1e18
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);
}
