//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@modules/common/OwnableModule.sol";

// solhint-disable-next-line no-empty-blocks
contract InitialModuleBeacon is OwnableModule, Initializable {
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract with an initial owner
    /// @param initialOwner The address to set as the initial owner
    function initialize(address initialOwner) public initializer {
        _getOwnableStorage().owner = initialOwner;
    }
}
