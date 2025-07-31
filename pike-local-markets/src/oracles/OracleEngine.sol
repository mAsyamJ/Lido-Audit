//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPToken} from "@interfaces/IPToken.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract OracleEngine is IOracleEngine, AccessControlUpgradeable {
    /// @custom:storage-location erc7201:pike.OE.core
    struct OracleEngineStorage {
        /**
         * @notice Mapping of asset address to its configuration
         */
        mapping(address => AssetConfig) configs;
    }

    bytes32 internal constant _CONFIGURATOR_PERMISSION = "CONFIGURATOR";

    /// keccak256(abi.encode(uint256(keccak256("pike.OE.core")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _ORACLE_ENGINE_STORAGE =
        0x79c5c3edc3173a93bc1571f1b7494470f1d3221dd503efa3fe2d1a0869f4a100;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param owner Address of the owner
     */
    function initialize(address owner, address configurator) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(_CONFIGURATOR_PERMISSION, configurator);
    }

    /**
     * @inheritdoc IOracleEngine
     */
    function setAssetConfig(
        address asset,
        address mainOracle,
        address fallbackOracle,
        uint256 lowerBoundRatio,
        uint256 upperBoundRatio
    ) external onlyRole(_CONFIGURATOR_PERMISSION) {
        if (
            (lowerBoundRatio != 0 && upperBoundRatio != 0)
                && lowerBoundRatio > upperBoundRatio
        ) {
            revert InvalidBounds();
        }

        if (mainOracle == address(0)) {
            revert InvalidMainOracle();
        }

        if (asset == address(0)) {
            revert InvalidAsset();
        }

        _getOracleEngineStorage().configs[asset] = AssetConfig({
            mainOracle: mainOracle,
            fallbackOracle: fallbackOracle,
            lowerBoundRatio: lowerBoundRatio,
            upperBoundRatio: upperBoundRatio
        });

        emit AssetConfigSet(
            asset, mainOracle, fallbackOracle, lowerBoundRatio, upperBoundRatio
        );
    }

    /**
     * @inheritdoc IOracleEngine
     */
    function getUnderlyingPrice(IPToken pToken)
        external
        view
        override
        returns (uint256)
    {
        return getPrice(pToken.asset());
    }

    /**
     * @inheritdoc IOracleEngine
     */
    function configs(address asset) external view returns (AssetConfig memory) {
        return _getOracleEngineStorage().configs[asset];
    }

    /**
     * @inheritdoc IOracleEngine
     */
    function getPrice(address asset) public view override returns (uint256 price) {
        AssetConfig storage config = _getOracleEngineStorage().configs[asset];

        try IOracleProvider(config.mainOracle).getPrice(asset) returns (
            uint256 mainOraclePrice
        ) {
            if (config.fallbackOracle == address(0)) {
                return mainOraclePrice;
            }

            try IOracleProvider(config.fallbackOracle).getPrice(asset) returns (
                uint256 fallbackOraclePrice
            ) {
                if (config.lowerBoundRatio != 0 && config.upperBoundRatio != 0) {
                    uint256 lowerBound =
                        fallbackOraclePrice * config.lowerBoundRatio / 1e18;
                    uint256 upperBound =
                        fallbackOraclePrice * config.upperBoundRatio / 1e18;

                    if (mainOraclePrice < lowerBound || mainOraclePrice > upperBound) {
                        revert BoundValidationFailed();
                    }
                }

                return mainOraclePrice;
            } catch {
                return mainOraclePrice;
            }
        } catch {
            if (config.fallbackOracle != address(0)) {
                try IOracleProvider(config.fallbackOracle).getPrice(asset) returns (
                    uint256 fallbackOraclePrice
                ) {
                    return fallbackOraclePrice;
                } catch {
                    revert InvalidFallbackOraclePrice();
                }
            } else {
                revert InvalidMainOraclePrice();
            }
        }
    }

    function _getOracleEngineStorage()
        internal
        pure
        returns (OracleEngineStorage storage data)
    {
        bytes32 s = _ORACLE_ENGINE_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
