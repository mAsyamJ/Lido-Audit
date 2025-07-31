// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

import {Deploy} from "script/Deploy.sol";

contract Testnet is Deploy {
    constructor() Deploy() {}

    function run() public payable {
        setUp();

        vm.createSelectFork(vm.envString(rpcs[0]));
        forks[0] = vm.activeFork();

        vm.startBroadcast(adminPrivateKey);

        deployBeacons();
        deployFactory("./deployments/base-sepolia-demo/Testnet.json");

        vm.stopBroadcast();
    }
}
