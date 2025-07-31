// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SafeScript} from "./SafeScript.sol";

contract Config is Script, SafeScript {
    uint256 deployerPrivateKey;
    uint256 adminPrivateKey;

    uint256[] public forks;

    address DEPLOYER;
    address ADMIN;

    //chain id to rpcs
    mapping(uint256 => string) rpcs;

    constructor() {
        rpcs[8453] = "BASE_RPC";
        rpcs[84_532] = "BASE_SEPOLIA_RPC";
        rpcs[42_161] = "ARB_RPC";
        rpcs[421_614] = "ARB_SEPOLIA_RPC";
        rpcs[10] = "OP_RPC";
        rpcs[11_155_420] = "OP_SEPOLIA_RPC";
        rpcs[80_069] = "BERA_BEPOLIA_RPC";
        rpcs[10_143] = "MONAD_TESTNET_RPC";
        rpcs[998] = "HYPER_TESTNET";
        rpcs[146] = "SONIC_MAINNET_RPC";
        rpcs[57_054] = "SONIC_TESTNET_RPC";
        rpcs[1301] = "UNICHAIN_SEPOLIA_RPC";
    }

    function setUp() internal {
        if (vm.envUint("HEX_PRIV_KEY") == 0) revert("No private keys found");
        deployerPrivateKey = vm.envUint("HEX_PRIV_KEY");
        adminPrivateKey = vm.envUint("MODERATOR_PRIV_KEY");
        DEPLOYER = vm.addr(deployerPrivateKey);
        ADMIN = vm.addr(adminPrivateKey);
    }

    function startsWith(string memory str, string memory prefix)
        internal
        pure
        returns (bool)
    {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        if (strBytes.length < prefixBytes.length) return false;
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }

    function getBaseDir(string memory chain, bool isDryRun)
        internal
        view
        returns (string memory)
    {
        string memory root = vm.projectRoot();
        string memory version = vm.envString("VERSION");
        return isDryRun
            ? string(abi.encodePacked(root, "/deployments/", version, "/", chain, "/dry-run"))
            : string(abi.encodePacked(root, "/deployments/", version, "/", chain));
    }

    function getDeploymentPath(string memory chain, uint256 protocolId)
        internal
        view
        returns (string memory)
    {
        string memory baseDir = getBaseDir(chain, vm.envBool("DRY_RUN"));
        return string(
            abi.encodePacked(
                baseDir, "/protocol-", vm.toString(protocolId), "/deploymentData.json"
            )
        );
    }

    function readDeploymentData(string memory chain, uint256 protocolId)
        internal
        view
        returns (
            address factoryAddress,
            address riskEngineAddress,
            address oracleEngineAddress,
            address timelockAddress
        )
    {
        string memory deploymentPath = getDeploymentPath(chain, protocolId);
        string memory json = vm.readFile(deploymentPath);

        factoryAddress = vm.parseJsonAddress(json, ".factoryAddress");
        riskEngineAddress = vm.parseJsonAddress(json, ".riskEngine");
        oracleEngineAddress = vm.parseJsonAddress(json, ".oracleEngine");
        timelockAddress = vm.parseJsonAddress(json, ".timelock");
    }

    function writeJsonFile(string memory filePath, string memory json) internal {
        if (vm.exists(filePath)) {
            console.log("File %s already exists, skipping", filePath);
            return;
        }
        console.log("Writing JSON to %s: %s", filePath, json);
        vm.writeFile(filePath, json);
        console.log("Created file at %s", filePath);
    }
}
