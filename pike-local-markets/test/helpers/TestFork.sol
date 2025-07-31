// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TestHelpers} from "@helpers/TestHelpers.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";

contract TestFork is TestHelpers {
    function init() public {
        setLocalState(false);
    }
}
