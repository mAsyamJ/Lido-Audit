//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RBACStorage} from "@storage/RBACStorage.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";

contract RBACMixin is RBACStorage, OwnableMixin {
    /**
     * @dev Checks if target address has permission or Admin
     */
    function checkPermissionOrAdmin(bytes32 permission, address target) internal view {
        _isPermissionValid(permission);
        if (!_getRBACStorage().permissions[permission][target] && target != _owner()) {
            revert PermissionDenied(permission, target);
        }
    }

    /**
     * @dev Checks if target address has permission
     */
    function checkPermission(bytes32 permission, address target) internal view {
        _checkPermission(permission, target);
    }

    /**
     * @dev Checks if target address has permission in specified pToken
     */
    function checkNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) internal view {
        _checkNestedPermission(permission, nestedAddress, target);
    }
}
