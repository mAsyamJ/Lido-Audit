//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRBAC {
    /**
     * @notice Emitted when an address has been granted permission
     * @param permission The permission
     * @param target The address that has been granted
     */
    event PermissionGranted(bytes32 permission, address target);

    /**
     * @notice Emitted when an address has been granted permission
     * @param permission The permission.
     * @param nestedAddress The nested address that has permission
     * @param target The address that has been granted
     */
    event NestedPermissionGranted(
        bytes32 permission, address nestedAddress, address target
    );

    /**
     * @notice Emitted when an address has been revoked permission
     * @param permission The permission.
     * @param target The address that has been revoked
     */
    event PermissionRevoked(bytes32 permission, address target);

    /**
     * @notice Emitted when an address has been revoked permission
     * @param permission The permission.
     * @param nestedAddress The nested address that has permission
     * @param target The address that has been revoked
     */
    event NestedPermissionRevoked(
        bytes32 permission, address nestedAddress, address target
    );

    /**
     * @notice Thrown when an address permission is already granted.
     */
    error AlreadyGranted();

    /**
     * @notice Thrown when an address permission is already revoked.
     */
    error AlreadyRevoked();

    /**
     * @notice grant permission for an address.
     * @param permission The permission to be granted.
     * @param target The address that has to be granted.
     */
    function grantPermission(bytes32 permission, address target) external;

    /**
     * @notice grant permission for an address.
     * @param permission The permission to be granted
     * @param nestedAddress The nested address that has permission
     * @param target The address that has to be granted
     */
    function grantNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) external;

    /**
     * @notice revoke permission for an address.
     * @param permission The permission to be revoked.
     * @param target The address that has to be revoked.
     */
    function revokePermission(bytes32 permission, address target) external;

    /**
     * @notice revoke permission for an address.
     * @param permission The permission to be revoked.
     * @param nestedAddress The nested address that has permission.
     * @param target The address that has to be revoked.
     */
    function revokeNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) external;

    /**
     * @notice check for an address permission.
     * @param permission The valid permission to be checked with target.
     * @param target The address to be checked.
     */
    function hasPermission(bytes32 permission, address target)
        external
        view
        returns (bool);

    /**
     * @notice check for an address permission.
     * @param permission The valid permission to be checked with target.
     * @param nestedAddress The nested address that has permission.
     * @param target The address to be checked.
     */
    function hasNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) external view returns (bool);
}
