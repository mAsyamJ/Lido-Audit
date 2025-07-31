// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

interface IChainlinkOracleProvider is IOracleProvider {
    /**
     * @notice Event emitted when asset configuration is set
     */
    event AssetConfigSet(
        address asset, AggregatorV3Interface feed, uint256 maxStalePeriod
    );

    /**
     * @notice Error emitted when asset is invalid
     */
    error InvalidAsset();

    /**
     * @notice Error emitted when returned price is not positive
     */
    error InvalidPrice();

    /**
     * @notice Error emitted when feed is invalid
     */
    error InvalidFeed();

    /**
     * @notice Error emitted when stale period is invalid
     */
    error InvalidStalePeriod();

    /**
     * @notice Error emitted when price is stale
     */
    error StalePrice();

    /**
     * @notice Error emitted when sequencer is down
     */
    error SequencerDown();

    /**
     * @notice Error emitted when grace period is not over
     */
    error GracePeriodNotOver();

    /**
     * @notice Set the asset configuration
     * @param asset Address of the asset
     * @param feed Chainlink feed for the asset
     * @param maxStalePeriod Maximum stale period for the price feed
     */
    function setAssetConfig(
        address asset,
        AggregatorV3Interface feed,
        uint256 maxStalePeriod
    ) external;
}
