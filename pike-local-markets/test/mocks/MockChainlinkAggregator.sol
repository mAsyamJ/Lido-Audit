//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

contract MockChainlinkAggregator is AggregatorV3Interface {
    uint8 public decimals;
    uint256 public price;
    uint256 public startedAt;
    uint256 public updatedAt;

    constructor() {
        decimals = 8;
    }

    function setDecimals(uint8 _decimals) external {
        decimals = _decimals;
    }

    function setRoundData(uint256 _price, uint256 _startedAt, uint256 _updatedAt)
        external
    {
        price = _price;
        startedAt = _startedAt;
        updatedAt = _updatedAt;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, int256(price), startedAt, updatedAt, 0);
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, int256(price), startedAt, updatedAt, 0);
    }

    function description() external pure returns (string memory) {
        return "ChainlinkAggregator";
    }

    function version() external pure returns (uint256) {
        return 0;
    }
}
