// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "cannon-std/Cannon.sol";
import "forge-std/Test.sol";

import {TestState} from "@helpers/TestState.sol";
import {Factory} from "@factory/Factory.sol";
import {Timelock} from "@governance/Timelock.sol";

import {IOwnable} from "@interfaces/IOwnable.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";
import {RiskEngineModule} from "@modules/riskEngine/RiskEngineModule.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

contract TestGetters is Test, TestState {
    using Cannon for Vm;

    function getAdmin() public view returns (address) {
        return _testState.admin;
    }

    function getPToken(string memory pToken) public view returns (PTokenModule token) {
        if (getLocatState()) {
            return PTokenModule(_testState.pTokens[keccak256(abi.encodePacked(pToken))]);
        } else {
            return PTokenModule(vm.getAddress(string.concat(pToken, ".Proxy")));
        }
    }

    function getIRM(string memory pToken)
        public
        view
        returns (IDoubleJumpRateModel irm)
    {
        if (getLocatState()) {
            return IDoubleJumpRateModel(
                _testState.pTokens[keccak256(abi.encodePacked(pToken))]
            );
        } else {
            return IDoubleJumpRateModel(vm.getAddress(string.concat(pToken, ".Proxy")));
        }
    }

    function getRiskEngine() public view returns (RiskEngineModule re) {
        if (getLocatState()) {
            return RiskEngineModule(_testState.riskEngine);
        } else {
            return RiskEngineModule(vm.getAddress("core.Proxy"));
        }
    }

    function getFactory() public view returns (Factory factory) {
        if (getLocatState()) {
            return Factory(_testState.factory);
        } else {
            return Factory(vm.getAddress("factory.Proxy"));
        }
    }

    function getTimelock() public view returns (Timelock timelock) {
        if (getLocatState()) {
            return Timelock(payable(_testState.timelock));
        } else {
            return Timelock(payable(vm.getAddress("timelock.Proxy")));
        }
    }

    function getPTokenOwner(string memory pToken) public view returns (address owner) {
        if (getLocatState()) {
            return IOwnable(address(getPToken(pToken))).owner();
        } else {
            return IOwnable(vm.getAddress(string.concat(pToken, ".Proxy"))).owner();
        }
    }

    function getCoreOwner() public view returns (address owner) {
        if (getLocatState()) {
            return IOwnable(address(getRiskEngine())).owner();
        } else {
            return IOwnable(vm.getAddress("core.Proxy")).owner();
        }
    }

    function getDebug() public view returns (bool) {
        return _testState.debug;
    }

    function getLocatState() public view returns (bool) {
        return _testState.localState;
    }

    function getOracle() public view returns (address) {
        return _testState.oracle;
    }
}
