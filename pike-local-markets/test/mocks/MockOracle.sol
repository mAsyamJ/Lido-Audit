// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import {IPToken} from "@interfaces/IPToken.sol";

contract MockOracle {
    mapping(address => uint256) prices;

    /// usd price with 6 decimals
    function setPrice(address pToken, uint256 price, uint256 decimals) external {
        prices[address(pToken)] = price * (10 ** (30 - decimals));
    }

    function getUnderlyingPrice(IPToken pToken) external view returns (uint256 price) {
        return prices[address(pToken)];
    }
}

contract MockProvider is IOracleProvider {
    mapping(address => uint256) prices;

    /// usd price with 6 decimals
    function setPrice(address asset, uint256 price, uint256 decimals) external {
        prices[asset] = price * (10 ** (30 - decimals));
    }

    function getPrice(address asset) external view returns (uint256 price) {
        return prices[address(asset)];
    }
}
