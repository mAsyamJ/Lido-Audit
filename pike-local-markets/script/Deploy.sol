// // SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {Config} from "script/Config.sol";
import {Factory} from "@factory/Factory.sol";
import {UpgradeableBeacon} from
    "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Config {
    string PATH;

    address reBeacon;
    address oeBeacon;
    address pTokenBeacon;
    address timelockBeacon;

    address factory;

    constructor() Config() {}

    function deployBeacons() internal {
        console.log("---------------");
        console.log("deploy-beacon-logs");

        address riskEngineImplementation = getAddress("RiskEngineRouter");
        address pTokenImplementation = getAddress("PTokenRouter");
        address oracleEngineImplementation = getAddress("OracleEngine");
        address timelockImplementation = getAddress("Timelock");

        reBeacon = address(new UpgradeableBeacon(riskEngineImplementation, ADMIN));
        console.log("deployed risk engine beacon:", reBeacon);

        oeBeacon = address(new UpgradeableBeacon(oracleEngineImplementation, ADMIN));
        console.log("deployed oracle engine beacon:", oeBeacon);

        pTokenBeacon = address(new UpgradeableBeacon(pTokenImplementation, ADMIN));
        console.log("deployed ptoken beacon:", pTokenBeacon);

        timelockBeacon = address(new UpgradeableBeacon(timelockImplementation, ADMIN));
        console.log("deployed timelock beacon:", timelockBeacon);
        console.log("---------------");
    }

    function deployFactory(string memory path) internal {
        console.log("---------------");
        console.log("deploy-factory-logs");

        bytes memory data = abi.encodeCall(
            Factory.initialize, (ADMIN, reBeacon, oeBeacon, pTokenBeacon, timelockBeacon)
        );
        console.logBytes(data);
        address factoryImplementation = address(new Factory());
        console.log("deployed factory Implementation:", factoryImplementation);
        writeAddress(path, "Factory Impl", factoryImplementation);

        factory = address(new ERC1967Proxy(factoryImplementation, data));
        console.log("deployed factory contract:", factory);
        console.log("---------------");

        writeAddress(path, "Factory", factory);
    }

    function getAddress(string memory name) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, PATH, name, ".json");
        bytes memory addr = vm.parseJson(vm.readFile(path), ".address");
        return abi.decode(addr, (address));
    }

    function writeAddress(string memory path, string memory name, address value)
        internal
    {
        vm.writeJson(vm.serializeAddress("contracts", name, value), path);
    }
}
