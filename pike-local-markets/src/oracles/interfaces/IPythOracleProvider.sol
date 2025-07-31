pragma solidity 0.8.28;

import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";

interface IPythOracleProvider is IOracleProvider {
    /**
     * @notice Event emitted when asset configuration is set
     */
    event AssetConfigSet(
        address asset, bytes32 feed, uint256 confidenceRatioMin, uint256 maxStalePeriod
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
     * @notice Error emitted when min confidence ratio is invalid
     */
    error InvalidMinConfRatio();

    /**
     * @notice Error emitted when max stale period is invalid
     */
    error InvalidMaxStalePeriod();

    /**
     * @notice Set the asset configuration
     * @param asset Address of the asset
     * @param feed Pyth feed for the asset
     * @param confidenceRatioMin Minimum confidence ratio for the price feed
     * @param maxStalePeriod Maximum stale period for the price feed
     */
    function setAssetConfig(
        address asset,
        bytes32 feed,
        uint256 confidenceRatioMin,
        uint256 maxStalePeriod
    ) external;
}
