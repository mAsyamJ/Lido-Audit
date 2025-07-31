//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {OwnableStorage} from "@storage/OwnableStorage.sol";

contract OwnableMixin is OwnableStorage {
    /**
     * @dev Reverts if the caller is not the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }
}
