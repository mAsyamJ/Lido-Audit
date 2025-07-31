//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPythOracleProvider} from "@oracles/interfaces/IPythOracleProvider.sol";
import {IPyth, PythStructs} from "@pythnetwork/IPyth.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Metadata} from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract PythOracleProvider is
    IPythOracleProvider,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    /// @custom:storage-location erc7201:pike.OE.provider
    struct OracleProviderStorage {
        /**
         * @notice Mapping of asset address to its configuration
         */
        mapping(address => AssetConfig) configs;
    }

    struct AssetConfig {
        /**
         * @notice Pyth feed for the asset
         */
        bytes32 feed;
        /**
         * @notice Minimum confidence ratio for the price feed
         */
        uint256 confidenceRatioMin;
        /**
         * @notice Maximum stale period for the price feed
         */
        uint256 maxStalePeriod;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.OE.provider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _ORACLE_PROVIDER_STORAGE =
        0x5fa1a95efabc4eee5395b3503834a3e8dddcd4f606102ddd245db9714a38bb00;

    /**
     * @notice Pyth oracle
     */
    IPyth public immutable pyth;

    /**
     * @notice Initial Owner to prevent manipulation during deployment
     */
    address public immutable initialOwner;

    /**
     * @notice Contract constructor
     * @param _pyth Pyth oracle address
     */
    constructor(address _pyth, address _initialOwner) {
        pyth = IPyth(_pyth);
        initialOwner = _initialOwner;
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     */
    function initialize() external initializer {
        __Ownable_init(initialOwner);
    }

    /**
     * @inheritdoc IPythOracleProvider
     */
    function setAssetConfig(
        address asset,
        bytes32 feed,
        uint256 confidenceRatioMin,
        uint256 maxStalePeriod
    ) external onlyOwner {
        if (asset == address(0)) {
            revert InvalidAsset();
        }

        if (maxStalePeriod == 0) {
            revert InvalidMaxStalePeriod();
        }

        _getProviderStorage().configs[asset] =
            AssetConfig(feed, confidenceRatioMin, maxStalePeriod);
        emit AssetConfigSet(asset, feed, confidenceRatioMin, maxStalePeriod);
    }

    /**
     * @notice Get the price of the asset
     * @param asset Address of the asset
     * @return Price of the asset scaled to (36 - assetDecimals) decimals
     */
    function getPrice(address asset) external view override returns (uint256) {
        AssetConfig memory config = _getProviderStorage().configs[asset];

        PythStructs.Price memory priceInfo =
            pyth.getPriceNoOlderThan(config.feed, config.maxStalePeriod);

        if (priceInfo.price <= 0) {
            revert InvalidPrice();
        }

        if (
            priceInfo.conf > 0
                && (uint64(priceInfo.price) / priceInfo.conf < config.confidenceRatioMin)
        ) {
            revert InvalidMinConfRatio();
        }

        uint256 priceIn18Decimals = (uint256(uint64(priceInfo.price)) * (10 ** 18))
            / (10 ** uint8(uint32(-1 * priceInfo.expo)));

        IERC20Metadata token = IERC20Metadata(asset);
        uint256 decimals = token.decimals();

        return priceIn18Decimals * (10 ** (18 - decimals));
    }

    /**
     * @notice Authorize upgrade
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _getProviderStorage()
        internal
        pure
        returns (OracleProviderStorage storage data)
    {
        bytes32 s = _ORACLE_PROVIDER_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
