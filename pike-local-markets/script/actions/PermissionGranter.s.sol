// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRBAC} from "@interfaces/IRBAC.sol";
import {Timelock} from "@governance/Timelock.sol";
import {Config, console} from "../Config.sol";

contract PermissionGranter is Config {
    IRBAC re;
    Timelock tm;

    // Mapping from permission names to bytes32 values
    mapping(string => bytes32) public permissionMap;

    constructor() Config() {
        // Initialize permission mappings
        permissionMap["CONFIGURATOR"] = "CONFIGURATOR";
        permissionMap["PROTOCOL_OWNER"] = "PROTOCOL_OWNER";
        permissionMap["OWNER_WITHDRAWER"] = "OWNER_WITHDRAWER";
        permissionMap["PAUSE_GUARDIAN"] = "PAUSE_GUARDIAN";
        permissionMap["BORROW_CAP_GUARDIAN"] = "BORROW_CAP_GUARDIAN";
        permissionMap["SUPPLY_CAP_GUARDIAN"] = "SUPPLY_CAP_GUARDIAN";
        permissionMap["RESERVE_MANAGER"] = "RESERVE_MANAGER";
        permissionMap["RESERVE_WITHDRAWER"] = "RESERVE_WITHDRAWER";
        permissionMap["EMERGENCY_WITHDRAWER"] = "EMERGENCY_WITHDRAWER";
    }

    function run() public payable {
        // Get parameters from environment variables
        string memory chain = vm.envString("CHAIN");
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");
        string memory permissionName = vm.envString("PERMISSION");
        address target = vm.envAddress("TARGET");

        // Convert permission name to bytes32
        bytes32 permission = permissionMap[permissionName];
        require(permission != bytes32(0), "Invalid permission name");

        // Read deployment data
        (, address riskEngineAddress,, address timelockAddress) =
            readDeploymentData(chain, protocolId);

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        re = IRBAC(riskEngineAddress);
        tm = Timelock(payable(timelockAddress));

        vm.startBroadcast(adminPrivateKey);
        grantPermission(permission, target);
        vm.stopBroadcast();
    }

    function grantPermission(bytes32 permission, address target) internal {
        console.log("=== Granting permission %s to %s ===", uint256(permission), target);

        re.grantPermission(permission, target);
    }
}
