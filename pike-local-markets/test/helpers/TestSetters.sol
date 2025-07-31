// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {TestStructs} from "@helpers/TestStructs.sol";
import {TestState} from "@helpers/TestState.sol";
import {TestGetters} from "@helpers/TestGetters.sol";

contract TestSetters is TestStructs, TestGetters {
    function setVm(Vm vm) public {
        _testState.vm = vm;
    }

    function setDebug(bool debug) public {
        _testState.debug = debug;
    }

    function setFactory(address factory) public {
        _testState.factory = factory;
    }

    function setTimelock(address timelock) public {
        _testState.timelock = timelock;
    }

    function setRiskEngine(address re) public {
        _testState.riskEngine = re;
    }

    function setOracle(address oracle_) public {
        _testState.oracle = oracle_;
    }

    function setPToken(string memory name, address pToken) public {
        _testState.pTokens[keccak256(abi.encodePacked(name))] = pToken;
    }

    function setLocalState(bool state) public {
        _testState.localState = state;
    }

    function setAdmin(address admin) public {
        _testState.admin = admin;
    }
}
