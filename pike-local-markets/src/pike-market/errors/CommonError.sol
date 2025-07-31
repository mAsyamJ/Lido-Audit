//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Library for common errors.
 */
library CommonError {
    /**
     * @dev Thrown when an operation is attempted on an already initialized contract.
     */
    error AlreadyInitialized();

    /**
     * @dev Thrown when a zero value is encountered.
     */
    error ZeroValue();

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    /**
     * @dev Thrown for arrays without parity.
     */
    error NoArrayParity();

    /**
     * @dev Thrown when an address representing a contract is expected, but no code is found at the address.
     */
    error NotAContract(address);

    /**
     * @dev Thrown when a zero address was passed as a function parameter (0x0000000000000000000000000000000000000000).
     */
    error ZeroAddress();

    /**
     * @dev Thrown when a permission is invalid
     */
    error InvalidPermission();
}
