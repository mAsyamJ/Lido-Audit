//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    IChainlinkOracleProvider,
    AggregatorV3Interface
} from "@oracles/interfaces/IChainlinkOracleProvider.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Metadata} from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ChainlinkOracleProvider is
    IChainlinkOracleProvider,
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
         * @notice Chainlink feed for the asset
         */
        AggregatorV3Interface feed;
        /**
         * @notice Maximum stale period for the price feed
         */
        uint256 maxStalePeriod;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.OE.provider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _ORACLE_PROVIDER_STORAGE =
        0x5fa1a95efabc4eee5395b3503834a3e8dddcd4f606102ddd245db9714a38bb00;

    /**
     * @notice Grace period time after the sequencer is back up
     */
    uint256 private constant GRACE_PERIOD_TIME = 3600;

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
     * @inheritdoc IChainlinkOracleProvider
     */
    function setAssetConfig(
        address asset,
        AggregatorV3Interface feed,
        uint256 maxStalePeriod
    ) external onlyOwner {
        if (asset == address(0)) {
            revert InvalidAsset();
        }

        if (address(feed) == address(0)) {
            revert InvalidFeed();
        }

        if (maxStalePeriod == 0) {
            revert InvalidStalePeriod();
        }

        _getProviderStorage().configs[asset] = AssetConfig(feed, maxStalePeriod);
        emit AssetConfigSet(asset, feed, maxStalePeriod);
    }

    /**
     * @notice Get the price of the asset
     * @param asset Address of the asset
     * @return Price of the asset scaled to (36 - assetDecimals) decimals
     */
    function getPrice(address asset) external view override returns (uint256) {
        _validateSequencerStatus();

        AssetConfig storage config = _getProviderStorage().configs[asset];
        uint256 priceDecimals = config.feed.decimals();
        (, int256 price,, uint256 updatedAt,) = config.feed.latestRoundData();
        if (price <= 0) {
            revert InvalidPrice();
        }

        if (block.timestamp - updatedAt > config.maxStalePeriod) {
            revert StalePrice();
        }

        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        return uint256(price) * (10 ** (36 - assetDecimals - priceDecimals));
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
