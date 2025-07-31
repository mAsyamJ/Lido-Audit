// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @title Pike Timelock Contract
 * @author NUTS Finance (hello@pike.finance)
 */
contract Timelock is TimelockControllerUpgradeable {
    bytes32 public constant EMERGENCY_GUARDIAN_ROLE = keccak256("EMERGENCY_GUARDIAN_ROLE");

    /**
     * @dev Emitted when a call is performed in an emergency execution flow.
     */
    event EmergencyCallExecuted(
        uint256 indexed index, address target, uint256 value, bytes data
    );

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param admin Address of timelock contract admin
     * @param protocolOwner Address of the protocol owner
     * @param guardian Address of the emergency guardian
     * @param minDelay minDelay of queue period
     * @param proposers array of proposers that are able to schedule an action
     * @param executors array of executes that are able to execute an action
     */
    function initialize(
        address admin,
        address protocolOwner,
        address guardian,
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) external initializer {
        __TimelockController_init(minDelay, proposers, executors, admin);
        _grantRole(CANCELLER_ROLE, protocolOwner);
        _grantRole(CANCELLER_ROLE, guardian);
        _grantRole(EMERGENCY_GUARDIAN_ROLE, guardian);
    }

    /**
     * @dev Execute an emergency operation containing a single transaction.
     * @dev Needs emergency guardian role access
     * @dev Does not store operation id
     * @dev Emits a {EmergencyCallExecuted} event.
     */
    function emergencyExecute(address target, uint256 value, bytes calldata payload)
        public
        payable
        onlyRole(EMERGENCY_GUARDIAN_ROLE)
    {
        _execute(target, value, payload);
        emit EmergencyCallExecuted(0, target, value, payload);
    }

    /**
     * @dev Execute an emergency operation containing a batch of transactions.
     * @dev Needs emergency guardian role access
     * @dev Does not store operation id
     * @dev Emits a {EmergencyCallExecuted} event.
     */
    function emergencyExecuteBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads
    ) public payable onlyRole(EMERGENCY_GUARDIAN_ROLE) {
        if (targets.length != values.length || targets.length != payloads.length) {
            revert TimelockInvalidOperationLength(
                targets.length, payloads.length, values.length
            );
        }

        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 value = values[i];
            bytes calldata payload = payloads[i];
            _execute(target, value, payload);
            emit EmergencyCallExecuted(i, target, value, payload);
        }
    }
}
