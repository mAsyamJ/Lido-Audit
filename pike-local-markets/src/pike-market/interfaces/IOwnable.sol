//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IOwnable {
    /**
     * @notice Emitted when an address has been nominated.
     * @param newOwner The address that has been nominated.
     */
    event OwnerNominated(address newOwner);

    /**
     * @notice Emitted when the owner of the contract has changed.
     * @param oldOwner The previous owner of the contract.
     * @param newOwner The new owner of the contract.
     */
    event OwnerChanged(address oldOwner, address newOwner);

    /**
     * @notice Thrown when an address tries to accept ownership but has not been nominated.
     */
    error NotNominated();

    /**
     * @notice Thrown when caller is not a pending nominated owner.
     */
    error NotPendingOwner();

    /**
     * @notice Thrown when an address is already nominated.
     */
    error AlreadyNominated();

    /**
     * @notice Allows a nominated address to accept ownership of the contract.
     * @dev Reverts if the caller is not nominated.
     */
    function acceptOwnership() external;

    /**
     * @notice Allows the current owner to transfer ownership a new owner.
     * @dev The owner does not need to accept ownership and go through nominating process.
     * @param newOwner The address that is to become owner.
     */
    function transferOwnership(address newOwner) external;

    /**
     * @notice Allows the current owner to nominate a new owner.
     * @dev The nominated owner will have to call `acceptOwnership` in a separate transaction
     * in order to finalize the action and become the new contract owner.
     * @param newNominatedOwner The address that is to become nominated.
     */
    function nominateNewOwner(address newNominatedOwner) external;

    /**
     * @notice Allows a nominated owner to reject the nomination.
     */
    function renounceNomination() external;

    /**
     * @notice Allows an owner to renounce ownership.
     */
    function renounceOwnership() external;

    /**
     * @notice Returns the current owner of the contract.
     */
    function owner() external view returns (address);

    /**
     * @notice Returns the current nominated owner of the contract.
     * @dev Only one address can be nominated at a time.
     */
    function pendingOwner() external view returns (address);
}
