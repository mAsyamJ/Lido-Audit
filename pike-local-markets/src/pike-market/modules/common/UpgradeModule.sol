//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UpgradeStorage} from "@storage/UpgradeStorage.sol";
import {OwnableStorage} from "@storage/OwnableStorage.sol";
import {CommonError} from "@errors/CommonError.sol";
import {IUpgrade} from "@interfaces/IUpgrade.sol";

/**
 * @title Contract for managing upgradeability
 * See IUpgrade.
 */
contract UpgradeModule is IUpgrade, UpgradeStorage, OwnableStorage {
    /**
     * @inheritdoc IUpgrade
     */
    function getImplementation() external view override returns (address) {
        return _getImplementationStorage().implementation;
    }

    /**
     * @inheritdoc IUpgrade
     */
    function upgradeTo(address newImplementation) public override {
        OwnableStorage._checkOwner();
        _upgradeTo(newImplementation);
    }

    /**
     * @inheritdoc IUpgrade
     */
    function simulateUpgradeTo(address newImplementation) public override {
        ProxyData storage data = _getImplementationStorage();

        data.simulatingUpgrade = true;

        address currentImplementation = data.implementation;
        data.implementation = newImplementation;

        (bool rollbackSuccessful,) = newImplementation.delegatecall(
            abi.encodeCall(this.upgradeTo, (currentImplementation))
        );

        if (
            !rollbackSuccessful
                || _getImplementationStorage().implementation != currentImplementation
        ) {
            revert UpgradeSimulationFailed();
        }

        data.simulatingUpgrade = false;

        // solhint-disable-next-line reason-string, gas-custom-errors
        revert();
    }

    function _upgradeTo(address newImplementation) internal virtual {
        if (newImplementation == address(0)) {
            revert CommonError.ZeroAddress();
        }

        if (!isContract(newImplementation)) {
            revert CommonError.NotAContract(newImplementation);
        }

        ProxyData storage data = _getImplementationStorage();

        if (!data.simulatingUpgrade && _implementationIsSterile(newImplementation)) {
            revert ImplementationIsSterile(newImplementation);
        }

        data.implementation = newImplementation;

        emit Upgraded(address(this), newImplementation);
    }

    function _implementationIsSterile(address candidateImplementation)
        internal
        virtual
        returns (bool)
    {
        (bool simulationReverted, bytes memory simulationResponse) = address(this)
            .delegatecall(abi.encodeCall(this.simulateUpgradeTo, (candidateImplementation)));

        return !simulationReverted
            && keccak256(abi.encodePacked(simulationResponse))
                == keccak256(abi.encodePacked(UpgradeSimulationFailed.selector));
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;

        assembly {
            size := extcodesize(account)
        }

        return size > 0;
    }
}
