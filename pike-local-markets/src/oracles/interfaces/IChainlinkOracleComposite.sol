// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

interface IChainlinkOracleComposite is IOracleProvider {
    struct AssetConfig {
        /**
         * @notice Array of up to 3 Chainlink feeds for the asset
         */
        AggregatorV3Interface[3] feeds;
        /**
         * @notice Array of flags indicating whether to invert each feed's price (true for 1/price)
         */
        bool[3] invertRates;
        /**
         * @notice Array of maximum stale periods for each feed
         */
        uint256[3] maxStalePeriods;
    }

    /**
     * @notice Event emitted when asset configuration is set
     */
    event AssetConfigSet(
        address indexed asset, AggregatorV3Interface[3] feeds, uint256[3] maxStalePeriods
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
     * @notice Set the asset configuration with up to 3 feeds
     * @param asset Address of the asset
     * @param feeds Array of up to 3 Chainlink feeds
     * @param invertRates Array of flags indicating whether to invert each feed's price
     * @param maxStalePeriods Array of maximum stale periods for each feed
     */
    function setAssetConfig(
        address asset,
        AggregatorV3Interface[3] memory feeds,
        bool[3] memory invertRates,
        uint256[3] memory maxStalePeriods
    ) external;

    /**
     * @notice @notice Returns the Chainlink oracle configuration for a given asset.
     * @param asset The address of the asset to fetch the configuration for.
     * @return The oracle configuration struct containing feeds, inversion flags, and max stale periods.
     */
    function getAssetConfig(address asset) external view returns (AssetConfig memory);
}
