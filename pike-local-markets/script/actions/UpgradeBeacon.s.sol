// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UpgradeableBeacon} from
    "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IOwnable} from "@interfaces/IOwnable.sol";
import {Config, console} from "../Config.sol";

contract UpgradeBeacon is Config {
    IFactory factory;

    constructor() Config() {}

    // Struct to hold beacon and implementation data
    struct BeaconUpgrade {
        string name;
        address beacon;
        address newImplementation;
        string jsonFile;
    }

    // Read deployment addresses from JSON files
    function readDeploymentAddress(
        string memory chain,
        string memory version,
        string memory fileName
    ) internal view returns (address) {
        string memory path = string(
            abi.encodePacked(
                "./deployments/", version, "/", chain, "/", fileName, ".json"
            )
        );
        if (!vm.exists(path)) {
            console.log("Deployment file %s not found, skipping", path);
            return address(0);
        }
        string memory json = vm.readFile(path);
        return vm.parseJsonAddress(json, ".address");
    }

    // Check and upgrade a single beacon with simulation support
    function checkAndUpgradeBeacon(
        BeaconUpgrade memory upgrade,
        bool dryRun,
        bool useSafe,
        address safeAddress,
        address admin
    ) internal {
        if (upgrade.newImplementation == address(0)) {
            console.log("No new implementation found for %s, skipping", upgrade.name);
            return;
        }

        address currentImpl = UpgradeableBeacon(upgrade.beacon).implementation();
        console.log(
            "%s Beacon: Current implementation %s, New implementation %s",
            upgrade.name,
            currentImpl,
            upgrade.newImplementation
        );

        if (currentImpl == upgrade.newImplementation) {
            console.log("%s Beacon implementation is up-to-date, skipping", upgrade.name);
            return;
        }

        console.log(
            "Preparing to upgrade %s Beacon to %s",
            upgrade.name,
            upgrade.newImplementation
        );

        bytes memory upgradeCalldata = abi.encodeWithSelector(
            UpgradeableBeacon.upgradeTo.selector, upgrade.newImplementation
        );

        if (useSafe) {
            // Simulate the upgrade call from the Safe address
            vm.prank(safeAddress);
            (bool simSuccess,) = upgrade.beacon.call(upgradeCalldata);
            if (!simSuccess) {
                console.log(
                    "Simulation failed for %s Beacon: Safe %s lacks permission or call reverted",
                    upgrade.name,
                    safeAddress
                );
                return;
            }
            console.log(
                "Simulation successful for %s Beacon from Safe %s",
                upgrade.name,
                safeAddress
            );

            if (!dryRun) {
                // Submit to Safe via executeSingle (assumes SafeScript inheritance)
                executeSingle(upgrade.beacon, 0, upgradeCalldata, true);
                console.log(
                    "Submitted Safe transaction to upgrade %s Beacon", upgrade.name
                );
            } else {
                console.log(
                    "Dry run: Simulated Safe upgrade for %s Beacon, no submission",
                    upgrade.name
                );
            }
        } else {
            // Simulate the upgrade call from the admin address
            vm.prank(admin);
            (bool simSuccess,) = upgrade.beacon.call(upgradeCalldata);
            if (!simSuccess) {
                console.log(
                    "Simulation failed for %s Beacon: Admin %s lacks permission or call reverted",
                    upgrade.name,
                    admin
                );
                return;
            }
            console.log(
                "Simulation successful for %s Beacon from admin %s", upgrade.name, admin
            );

            if (!dryRun) {
                vm.startBroadcast(adminPrivateKey);
                UpgradeableBeacon(upgrade.beacon).upgradeTo(upgrade.newImplementation);
                vm.stopBroadcast();
                console.log("Broadcasted %s Beacon upgrade via EOA", upgrade.name);
            } else {
                console.log(
                    "Dry run: Simulated EOA upgrade for %s Beacon, no broadcast",
                    upgrade.name
                );
            }
        }
    }

    function run() public payable {
        string memory chain = vm.envString("CHAIN");
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");
        string memory version = vm.envString("VERSION");
        bool dryRun = vm.envBool("DRY_RUN");
        address safeAddress = vm.envOr("SAFE_ADDRESS", address(0));
        bool useSafe = safeAddress != address(0);

        console.log("safeAddress: %s, useSafe: %s", safeAddress, useSafe);
        console.log("Dry run: %s", dryRun);
        console.log(
            "Chain: %s, Chain ID: %s, Protocol ID: %s", chain, chainId, protocolId
        );

        // Read Factory address from deployment data
        (address factoryAddress,,,) = readDeploymentData(chain, protocolId);

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        factory = IFactory(factoryAddress);
        address admin = IOwnable(factoryAddress).owner();
        console.log("Admin address: %s", admin);

        // Define beacons to check
        BeaconUpgrade[] memory upgrades = new BeaconUpgrade[](4);
        upgrades[0] = BeaconUpgrade({
            name: "RiskEngine",
            beacon: factory.riskEngineBeacon(),
            newImplementation: readDeploymentAddress(chain, version, "RiskEngineRouter"),
            jsonFile: "RiskEngineRouter"
        });
        upgrades[1] = BeaconUpgrade({
            name: "OracleEngine",
            beacon: factory.oracleEngineBeacon(),
            newImplementation: readDeploymentAddress(chain, version, "OracleEngine"),
            jsonFile: "OracleEngine"
        });
        upgrades[2] = BeaconUpgrade({
            name: "Timelock",
            beacon: factory.timelockBeacon(),
            newImplementation: readDeploymentAddress(chain, version, "Timelock"),
            jsonFile: "Timelock"
        });
        upgrades[3] = BeaconUpgrade({
            name: "PToken",
            beacon: factory.pTokenBeacon(),
            newImplementation: readDeploymentAddress(chain, version, "PTokenRouter"),
            jsonFile: "PTokenRouter"
        });

        if (useSafe) {
            configureSafe(safeAddress, chainId);
        }

        // Process each beacon
        for (uint256 i = 0; i < upgrades.length; i++) {
            checkAndUpgradeBeacon(upgrades[i], dryRun, useSafe, safeAddress, admin);
        }
    }
}
