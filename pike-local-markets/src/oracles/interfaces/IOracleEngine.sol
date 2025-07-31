// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPToken} from "@interfaces/IPToken.sol";

interface IOracleEngine {
    struct AssetConfig {
        /**
         * @notice Main oracle address for the asset
         */
        address mainOracle;
        /**
         * @notice Fallback oracle address for the asset
         */
        address fallbackOracle;
        /**
         * @notice Lower bound ratio for the main oracle price to be considered valid
         * @dev Scaled by 1e18 i.e., 1e18 = 1
         */
        uint256 lowerBoundRatio;
        /**
         * @notice Upper bound ratio for the main oracle price to be considered valid
         * @dev Scaled by 1e18 i.e., 1e18 = 1
         */
        uint256 upperBoundRatio;
    }

    /**
     * @notice Event emitted when asset configuration is set
     */
    event AssetConfigSet(
        address indexed asset,
        address mainOracle,
        address fallbackOracle,
        uint256 lowerBoundRatio,
        uint256 upperBoundRatio
    );

    /**
     * @notice Error emitted when bounds are invalid
     */
    error InvalidBounds();

    /**
     * @notice Error emitted when main oracle is invalid
     */
    error InvalidMainOracle();

    /**
     * @notice Error emitted when asset is invalid
     */
    error InvalidAsset();

    /**
     * @notice Error emitted when bounds validation fails
     */
    error BoundValidationFailed();

    /**
     * @notice Error emitted when fallback oracle is invalid
     */
    error InvalidFallbackOraclePrice();

    /**
     * @notice Error emitted when main oracle price is invalid
     */
    error InvalidMainOraclePrice();

    /**
     * @notice Set asset configuration
     * @param asset Address of the asset
     * @param mainOracle Address of the main oracle
     * @param fallbackOracle Address of the fallback oracle
     * @param lowerBoundRatio Lower bound ratio for the main oracle price to be considered valid
     * @param upperBoundRatio Upper bound ratio for the main oracle price to be considered valid
     */
    function setAssetConfig(
        address asset,
        address mainOracle,
        address fallbackOracle,
        uint256 lowerBoundRatio,
        uint256 upperBoundRatio
    ) external;

    /**
     * @notice Get the price of a pToken's underlying asset
     * @param pToken The pToken address
     * @return price The price of the asset
     */
    function getUnderlyingPrice(IPToken pToken) external view returns (uint256);

    /**
     * @notice Get the price of a asset
     * @param asset The address of the asset
     * @return price The price of the asset
     */
    function getPrice(address asset) external view returns (uint256);

    /**
     * @notice Get the configs of a asset
     * @param asset The address of the  underlying asset
     */
    function configs(address asset) external view returns (AssetConfig memory);
}
