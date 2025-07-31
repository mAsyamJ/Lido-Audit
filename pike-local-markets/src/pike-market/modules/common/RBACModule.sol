//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRBAC} from "@interfaces/IRBAC.sol";
import {RBACMixin} from "@utils/RBACMixin.sol";
import {CommonError} from "@errors/CommonError.sol";

/**
 * @title Contract for facilitating role based access control.
 * See IRBAC.
 */
contract RBACModule is IRBAC, RBACMixin {
    /**
     * @inheritdoc IRBAC
     */
    function grantPermission(bytes32 permission, address target) external onlyOwner {
        if (_hasPermission(permission, target)) {
            revert AlreadyGranted();
        }
        _getRBACStorage().permissions[permission][target] = true;
        emit PermissionGranted(permission, target);
    }

    /**
     * @inheritdoc IRBAC
     */
    function grantNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) external onlyOwner {
        if (_hasNestedPermission(permission, nestedAddress, target)) {
            revert AlreadyGranted();
        }
        _getRBACStorage().nestedPermissions[permission][nestedAddress][target] = true;
        emit NestedPermissionGranted(permission, nestedAddress, target);
    }

    /**
     * @inheritdoc IRBAC
     */
    function revokePermission(bytes32 permission, address target) external onlyOwner {
        if (!_hasPermission(permission, target)) {
            revert AlreadyRevoked();
        }

        _getRBACStorage().permissions[permission][target] = false;
        emit PermissionRevoked(permission, target);
    }

    /**
     * @inheritdoc IRBAC
     */
    function revokeNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) external onlyOwner {
        if (!_hasNestedPermission(permission, nestedAddress, target)) {
            revert AlreadyRevoked();
        }

        _getRBACStorage().nestedPermissions[permission][nestedAddress][target] = false;
        emit NestedPermissionRevoked(permission, nestedAddress, target);
    }

    /**
     * @inheritdoc IRBAC
     */
    function hasPermission(bytes32 permission, address target)
        external
        view
        returns (bool)
    {
        return _hasPermission(permission, target);
    }

    /**
     * @inheritdoc IRBAC
     */
    function hasNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) external view returns (bool) {
        return _hasNestedPermission(permission, nestedAddress, target);
    }

    function _hasPermission(bytes32 permission, address target)
        internal
        view
        returns (bool)
    {
        if (target == address(0)) {
            revert CommonError.ZeroAddress();
        }

        _isPermissionValid(permission);

        return _getRBACStorage().permissions[permission][target];
    }

    function _hasNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) internal view returns (bool) {
        if (target == address(0) || nestedAddress == address(0)) {
            revert CommonError.ZeroAddress();
        }

        _isPermissionValid(permission);

        return _getRBACStorage().nestedPermissions[permission][nestedAddress][target];
    }
}
