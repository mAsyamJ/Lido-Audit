//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Library for interest rate models errors.
 */
library IRMError {
    /**
     * @dev Thrown when base rate is not zero while initial multiplier is zero
     */
    error InvalidMultiplierForNonZeroBaseRate();

    /**
     * @dev Thrown when kink or jump multiplier order is not correct.
     */
    error InvalidKinkOrMultiplierOrder();
}
