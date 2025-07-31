//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

abstract contract RBACStorage {
    /// @custom:storage-location erc7201:pike.LM.RBAC
    struct RBACData {
        mapping(bytes32 => mapping(address => bool)) permissions;
        mapping(bytes32 => mapping(address => mapping(address => bool))) nestedPermissions;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.RBAC")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _SLOT_RBAC_STORAGE =
        0xd21fdb8e4b687c9e7355e21e2f4695df714198f0142124262187b209674d2600;

    bytes32 internal constant _CONFIGURATOR_PERMISSION = "CONFIGURATOR";
    bytes32 internal constant _PROTOCOL_OWNER_PERMISSION = "PROTOCOL_OWNER";
    bytes32 internal constant _OWNER_WITHDRAWER_PERMISSION = "OWNER_WITHDRAWER";
    bytes32 internal constant _PAUSE_GUARDIAN_PERMISSION = "PAUSE_GUARDIAN";
    bytes32 internal constant _BORROW_CAP_GUARDIAN_PERMISSION = "BORROW_CAP_GUARDIAN";
    bytes32 internal constant _SUPPLY_CAP_GUARDIAN_PERMISSION = "SUPPLY_CAP_GUARDIAN";
    bytes32 internal constant _RESERVE_MANAGER_PERMISSION = "RESERVE_MANAGER";
    bytes32 internal constant _RESERVE_WITHDRAWER_PERMISSION = "RESERVE_WITHDRAWER";
    bytes32 internal constant _EMERGENCY_WITHDRAWER_PERMISSION = "EMERGENCY_WITHDRAWER";

    error PermissionDenied(bytes32, address);
    error NestedPermissionDenied(bytes32, address, address);
    error InvalidPermission();

    function _checkPermission(bytes32 permission, address target) internal view virtual {
        _isPermissionValid(permission);
        if (!_getRBACStorage().permissions[permission][target]) {
            revert PermissionDenied(permission, target);
        }
    }

    function _checkNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) internal view virtual {
        _isPermissionValid(permission);
        if (!_getRBACStorage().nestedPermissions[permission][nestedAddress][target]) {
            revert NestedPermissionDenied(permission, nestedAddress, target);
        }
    }

    function _isPermissionValid(bytes32 permission) internal pure {
        if (
            permission != _CONFIGURATOR_PERMISSION
                && permission != _OWNER_WITHDRAWER_PERMISSION
                && permission != _EMERGENCY_WITHDRAWER_PERMISSION
                && permission != _PROTOCOL_OWNER_PERMISSION
                && permission != _PAUSE_GUARDIAN_PERMISSION
                && permission != _BORROW_CAP_GUARDIAN_PERMISSION
                && permission != _SUPPLY_CAP_GUARDIAN_PERMISSION
                && permission != _RESERVE_MANAGER_PERMISSION
                && permission != _RESERVE_WITHDRAWER_PERMISSION
        ) {
            revert InvalidPermission();
        }
    }

    function _getRBACStorage() internal pure returns (RBACData storage $) {
        bytes32 s = _SLOT_RBAC_STORAGE;
        assembly {
            $.slot := s
        }
    }
}
