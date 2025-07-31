// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TestHelpers} from "@helpers/TestHelpers.sol";

contract TestLocal is TestHelpers {
    function init() public {
        setLocalState(true);
        deployProtocol();
    }

    function initFactory() public {
        setLocalState(true);
        deployProtocolFactory();
    }
}
