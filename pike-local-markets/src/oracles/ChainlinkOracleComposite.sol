// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    IChainlinkOracleComposite,
    AggregatorV3Interface
} from "@oracles/interfaces/IChainlinkOracleComposite.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Metadata} from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract ChainlinkOracleComposite is
    IChainlinkOracleComposite,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    using Math for uint256;
    /// @custom:storage-location erc7201:pike.OE.provider

    struct OracleProviderStorage {
        /**
         * @notice Mapping of asset address to its configuration
         */
        mapping(address => AssetConfig) configs;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.OE.provider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _ORACLE_PROVIDER_STORAGE =
        0x5fa1a95efabc4eee5395b3503834a3e8dddcd4f606102ddd245db9714a38bb00;

    /**
     * @notice Grace period time after the sequencer is back up
     */
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    /**
     * @notice Number of decimals used for intermediate price scaling
     */
    uint256 private constant SCALING_DECIMALS = 36;

    /**
     * @notice Scaling factor derived from SCALING_DECIMALS
     */
    uint256 private constant SCALING_FACTOR = 10 ** SCALING_DECIMALS;

    /**
     * @notice Chainlink feed for the sequencer uptime
     */
    AggregatorV3Interface public immutable sequencerUptimeFeed;

    /**
     * @notice Initial Owner to prevent manipulation during deployment
     */
    address public immutable initialOwner;

    /**
     * @notice Contract constructor
     * @param _sequencerUptimeFeed L2 Sequencer uptime feed
     * @param _initialOwner Address of the initial owner
     */
    constructor(AggregatorV3Interface _sequencerUptimeFeed, address _initialOwner) {
        sequencerUptimeFeed = _sequencerUptimeFeed;
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
     * @inheritdoc IChainlinkOracleComposite
     */
    function setAssetConfig(
        address asset,
        AggregatorV3Interface[3] memory feeds,
        bool[3] memory invertRates,
        uint256[3] memory maxStalePeriods
    ) external onlyOwner {
        if (asset == address(0)) revert InvalidAsset();

        if (address(feeds[0]) == address(0)) {
            revert InvalidFeed();
        }

        if (maxStalePeriods[0] == 0) {
            revert InvalidStalePeriod();
        }

        AssetConfig storage config = _getProviderStorage().configs[asset];
        config.feeds = feeds;
        config.invertRates = invertRates;
        config.maxStalePeriods = maxStalePeriods;

        emit AssetConfigSet(asset, feeds, maxStalePeriods);
    }

    /**
     * @inheritdoc IChainlinkOracleComposite
     */
    function getAssetConfig(address asset)
        external
        view
        override
        returns (AssetConfig memory)
    {
        return _getProviderStorage().configs[asset];
    }

    /**
     * @notice Get the price of the asset by processing up to 3 feeds
     * @param asset Address of the asset
     * @return Price of the asset scaled to (36 - assetDecimals) decimals
     */
    function getPrice(address asset) external view override returns (uint256) {
        _validateSequencerStatus();
        AssetConfig storage config = _getProviderStorage().configs[asset];

        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        uint256 compositePrice = SCALING_FACTOR;

        for (uint8 i = 0; i < 3; i++) {
            AggregatorV3Interface feed = config.feeds[i];
            if (address(feed) == address(0)) continue;

            uint8 feedDecimals = feed.decimals();
            (, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
            if (price <= 0) revert InvalidPrice();
            if (block.timestamp - updatedAt > config.maxStalePeriods[i]) {
                revert StalePrice();
            }

            uint256 rate;
            if (config.invertRates[i]) {
                rate = SCALING_FACTOR.mulDiv((10 ** feedDecimals), uint256(price));
            } else {
                rate = uint256(price) * (10 ** (SCALING_DECIMALS - feedDecimals));
            }
            compositePrice = compositePrice.mulDiv(rate, SCALING_FACTOR);
        }
        return compositePrice / (10 ** assetDecimals);
    }

    /**
     * @notice Authorize upgrade
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Validate the sequencer status
     */
    function _validateSequencerStatus() internal view {
        if (address(sequencerUptimeFeed) == address(0)) {
            return;
        }

        (
            /*uint80 roundID*/
            ,
            int256 answer,
            uint256 startedAt,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = sequencerUptimeFeed.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert SequencerDown();
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) {
            revert GracePeriodNotOver();
        }
    }

    /**
     * @notice Get the storage location for OracleProviderStorage
     * @return data Storage reference to the OracleProviderStorage struct
     */
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
