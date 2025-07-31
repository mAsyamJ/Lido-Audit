// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {Timelock} from "@governance/Timelock.sol";
import {Config, console} from "../Config.sol";

contract DeployProtocol is Config {
    struct DeploymentData {
        string version;
        string chain;
        address factoryAddress;
        address riskEngine;
        address oracleEngine;
        address timelock;
        uint256 protocolId;
        bool isDryRun;
    }

    struct ProtocolInfo {
        address initialGovernor;
        address emergencyExecutor;
        uint256 ownerShareMantissa;
        uint256 configuratorShareMantissa;
    }

    DeploymentData public deployData;
    IFactory public factory;
    IRiskEngine public re;
    IOracleEngine public oe;
    Timelock public tm;

    constructor() Config() {}

    function getAddresses(string memory path) internal view returns (address) {
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json, ".address");
        return abi.decode(data, (address));
    }

    function readProtocolInfo() internal view returns (ProtocolInfo memory) {
        string memory configPath = vm.envString("CONFIG_PATH");
        string memory json = vm.readFile(configPath);
        return ProtocolInfo({
            initialGovernor: vm.parseJsonAddress(json, ".protocol-info.initialGovernor"),
            emergencyExecutor: vm.parseJsonAddress(json, ".protocol-info.emergencyExecutor"),
            ownerShareMantissa: vm.parseJsonUint(json, ".protocol-info.ownerShareMantissa"),
            configuratorShareMantissa: vm.parseJsonUint(
                json, ".protocol-info.configuratorShareMantissa"
            )
        });
    }

    function getBaseOutputDir(DeploymentData storage data)
        internal
        view
        returns (string memory)
    {
        if (data.isDryRun) {
            return string(
                abi.encodePacked(
                    "./deployments/", data.version, "/", data.chain, "/dry-run"
                )
            );
        } else {
            return
                string(abi.encodePacked("./deployments/", data.version, "/", data.chain));
        }
    }

    function getProtocolOutputDir(DeploymentData storage data)
        internal
        view
        returns (string memory)
    {
        string memory baseDir = getBaseOutputDir(data);
        return
            string(abi.encodePacked(baseDir, "/protocol-", vm.toString(data.protocolId)));
    }

    function writeDeploymentData() internal {
        string memory protocolDir = getProtocolOutputDir(deployData);
        vm.createDir(protocolDir, true);
        string memory outputPath =
            string(abi.encodePacked(protocolDir, "/deploymentData.json"));
        string memory obj = "deployData";
        vm.serializeUint(obj, "protocolId", deployData.protocolId);
        vm.serializeAddress(obj, "factoryAddress", deployData.factoryAddress);
        vm.serializeAddress(obj, "riskEngine", deployData.riskEngine);
        vm.serializeAddress(obj, "oracleEngine", deployData.oracleEngine);
        vm.serializeAddress(obj, "timelock", deployData.timelock);
        vm.serializeAddress(obj, "initialGovernor", ADMIN);
        vm.serializeAddress(obj, "emergencyExecutor", ADMIN);
        vm.serializeUint(obj, "deploymentTimestamp", block.timestamp);
        string memory jsonContent = vm.serializeBool(obj, "isDryRun", deployData.isDryRun);
        vm.writeJson(jsonContent, outputPath);
    }

    function deployProtocolComponents(uint256 protocolId, bool useSafe) internal {
        ProtocolInfo memory info = readProtocolInfo();

        console.log("Deploying protocol: %s", protocolId);
        bytes memory deployCalldata = abi.encodeWithSelector(
            IFactory.deployProtocol.selector,
            info.initialGovernor,
            info.emergencyExecutor,
            info.ownerShareMantissa,
            info.configuratorShareMantissa
        );

        address riskEngine;
        address oracleEngine;
        address payable governorTimelock;

        if (useSafe) {
            // Simulate the call as the current owner
            vm.prank(vm.envOr("SAFE_ADDRESS", address(0)));
            (bool success, bytes memory returnData) =
                deployData.factoryAddress.call(deployCalldata);
            require(success, "Simulation failed: deployProtocol reverted");

            // Decode returnData to get predicted addresses
            (riskEngine, oracleEngine, governorTimelock) =
                abi.decode(returnData, (address, address, address));

            // Submit to Safe Transaction Service if not dry-run
            executeSingle(
                deployData.factoryAddress, 0, deployCalldata, !deployData.isDryRun
            );

            re = IRiskEngine(riskEngine);
            oe = IOracleEngine(oracleEngine);
            tm = Timelock(governorTimelock);

            console.log("Predicted risk engine: %s", address(re));
            console.log("Predicted oracle engine: %s", address(oe));
            console.log("Predicted timelock: %s", address(tm));

            deployData.riskEngine = address(re);
            deployData.oracleEngine = address(oe);
            deployData.timelock = address(tm);

            if (!deployData.isDryRun) {
                console.log(
                    "Transaction sent to Safe. Addresses are predictions until executed."
                );
                console.log(
                    "Ensure the Safe is the factory owner or has permission to call deployProtocol."
                );
            }
        } else {
            vm.startBroadcast(adminPrivateKey);
            (riskEngine, oracleEngine, governorTimelock) = factory.deployProtocol(
                info.initialGovernor,
                info.emergencyExecutor,
                info.ownerShareMantissa,
                info.configuratorShareMantissa
            );
            vm.stopBroadcast();

            re = IRiskEngine(riskEngine);
            oe = IOracleEngine(oracleEngine);
            tm = Timelock(governorTimelock);

            console.log("Deployed risk engine: %s", address(re));
            console.log("Deployed oracle engine: %s", address(oe));
            console.log("Deployed timelock: %s", address(tm));

            deployData.riskEngine = address(re);
            deployData.oracleEngine = address(oe);
            deployData.timelock = address(tm);
        }
    }

    function run() public payable {
        string memory chain = vm.envString("CHAIN");
        uint256 chainId = vm.envUint("CHAIN_ID");
        string memory version = vm.envString("VERSION");
        bool dryRun = vm.envBool("DRY_RUN");
        address safeAddress = vm.envOr("SAFE_ADDRESS", address(0));
        bool useSafe = safeAddress != address(0);

        string memory path = string(
            abi.encodePacked("./deployments/", version, "/", chain, "/factory.Proxy.json")
        );
        console.log("Using deployment path: %s", path);

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        address factoryAddress = getAddresses(path);
        console.log("Factory address: %s", factoryAddress);
        factory = IFactory(factoryAddress);

        uint256 protocolId = factory.protocolCount() + 1;
        require(
            protocolId == vm.envUint("PROTOCOL_ID"),
            "Deploying ID does not match the specified ID."
        );

        deployData.version = version;
        deployData.chain = chain;
        deployData.factoryAddress = factoryAddress;
        deployData.protocolId = protocolId;
        deployData.isDryRun = dryRun;

        if (useSafe) {
            configureSafe(safeAddress, chainId);
        }

        if (useSafe && !dryRun) {
            string memory privKey = vm.envString("PRIVATE_KEY");
            uint256 privateKey = vm.parseUint(privKey);
            adminPrivateKey = privateKey;
            deployProtocolComponents(protocolId, true);
        } else {
            deployProtocolComponents(protocolId, useSafe);
        }

        console.log("Writing deployment data to JSON file...");
        writeDeploymentData();
    }
}
