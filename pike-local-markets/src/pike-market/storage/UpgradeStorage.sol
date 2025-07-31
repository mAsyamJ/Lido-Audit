//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract UpgradeStorage {
    /// @custom:storage-location erc7201:eip1967.proxy.implementation
    struct ProxyData {
        address implementation;
        bool simulatingUpgrade;
    }

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function _getImplementationStorage() internal pure returns (ProxyData storage data) {
        bytes32 s = _IMPLEMENTATION_SLOT;
        assembly {
            data.slot := s
        }
    }
}
