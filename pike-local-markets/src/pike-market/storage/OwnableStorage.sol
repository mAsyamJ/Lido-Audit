//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

abstract contract OwnableStorage {
    /// @custom:storage-location erc7201:pike.core.Ownable
    struct Ownable2StepStorage {
        address owner;
        address pendingOwner;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.core.Ownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _SLOT_OWNABLE_STORAGE =
        0x74d6be38627e7912e34c50c5cbc5a4826c01ce9f17c41aaeea1b0611189c7000;

    error Unauthorized(address);

    function _checkOwner() internal view virtual {
        if (msg.sender != _owner()) {
            revert Unauthorized(msg.sender);
        }
    }

    function _owner() internal view virtual returns (address) {
        return _getOwnableStorage().owner;
    }

    function _pendingOwner() internal view virtual returns (address) {
        return _getOwnableStorage().pendingOwner;
    }

    function _getOwnableStorage() internal pure returns (Ownable2StepStorage storage $) {
        bytes32 s = _SLOT_OWNABLE_STORAGE;
        assembly {
            $.slot := s
        }
    }
}
