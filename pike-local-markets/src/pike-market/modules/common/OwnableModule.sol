//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IOwnable} from "@interfaces/IOwnable.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";
import {CommonError} from "@errors/CommonError.sol";

/**
 * @title Contract for facilitating ownership by a single address with 2 steps.
 * See IOwnable.
 */
contract OwnableModule is IOwnable, OwnableMixin {
    /**
     * @inheritdoc IOwnable
     */
    function transferOwnership(address newOwner) external override onlyOwner {
        Ownable2StepStorage storage data = _getOwnableStorage();

        address oldOwner = data.owner;
        if (newOwner == address(0)) {
            revert CommonError.ZeroAddress();
        }

        data.owner = newOwner;
        emit OwnerChanged(oldOwner, newOwner);
    }

    /**
     * @inheritdoc IOwnable
     */
    function renounceNomination() external override {
        Ownable2StepStorage storage data = _getOwnableStorage();

        if (data.pendingOwner != msg.sender) {
            revert NotNominated();
        }

        data.pendingOwner = address(0);
    }

    /**
     * @inheritdoc IOwnable
     */
    function renounceOwnership() external override onlyOwner {
        Ownable2StepStorage storage data = _getOwnableStorage();

        address oldOwner = data.owner;
        data.owner = address(0);
        data.pendingOwner = address(0);

        emit OwnerChanged(oldOwner, address(0));
    }

    /**
     * @inheritdoc IOwnable
     */
    function acceptOwnership() public override {
        Ownable2StepStorage storage data = _getOwnableStorage();

        address nominatedOwner = data.pendingOwner;
        if (msg.sender != nominatedOwner) {
            revert NotPendingOwner();
        }

        emit OwnerChanged(data.owner, nominatedOwner);
        data.owner = nominatedOwner;

        data.pendingOwner = address(0);
    }

    /**
     * @inheritdoc IOwnable
     */
    function nominateNewOwner(address newNominatedOwner) public override onlyOwner {
        Ownable2StepStorage storage data = _getOwnableStorage();

        if (newNominatedOwner == address(0)) {
            revert CommonError.ZeroAddress();
        }

        if (newNominatedOwner == data.pendingOwner) {
            revert AlreadyNominated();
        }

        data.pendingOwner = newNominatedOwner;
        emit OwnerNominated(newNominatedOwner);
    }

    /**
     * @inheritdoc IOwnable
     */
    function owner() public view returns (address) {
        return _owner();
    }

    /**
     * @inheritdoc IOwnable
     */
    function pendingOwner() public view returns (address) {
        return _pendingOwner();
    }
}
