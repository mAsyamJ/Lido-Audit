// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract UUPSUpgradeableMock is UUPSUpgradeable {
    /// we declare this event to get the proxy address as well which is needed in cannon deployment
    /**
     * @notice Emitted when the implementation of the proxy has been upgraded.
     * @param self The address of the proxy whose implementation was upgraded.
     * @param implementation The address of the proxy's new implementation.
     */
    event Upgraded2(address indexed self, address implementation);

    function _authorizeUpgrade(address) internal override {}

    function upgradeToAndCall(address newImplementation, bytes memory data)
        public
        payable
        virtual
        override
        onlyProxy
    {
        super.upgradeToAndCall(newImplementation, data);

        emit Upgraded2(address(this), newImplementation);
    }
}
