pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {TestFuzz} from "@helpers/TestFuzz.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {ChainlinkOracleComposite} from "@oracles/ChainlinkOracleComposite.sol";
import {IChainlinkOracleComposite} from
    "@oracles/interfaces/IChainlinkOracleComposite.sol";
import {MockChainlinkAggregator} from "@mocks/MockChainlinkAggregator.sol";
import "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

contract FuzzOracle is TestFuzz {
    IPToken pWSTETH;

    ChainlinkOracleComposite chainlinkOracleComposite;
    MockChainlinkAggregator sequencerUptimeFeed;
    MockChainlinkAggregator mockRateFeed1;
    MockChainlinkAggregator mockRateFeed2;
    MockChainlinkAggregator mockPriceFeed1;

    uint256 startTimestamp = 1_726_655_826;
    uint256 gracePeriod = 3600;

    address weth;
    address wsteth;

    function setUp() public {
        setDebug(false);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        deployPToken(
            "pike-wsteth", "pWSTETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken
        );

        pWSTETH = getPToken("pWSTETH");

        vm.warp(startTimestamp);

        // deploy sequencer uptime feed
        sequencerUptimeFeed = new MockChainlinkAggregator();
        sequencerUptimeFeed.setRoundData(
            0, block.timestamp - gracePeriod - 1, block.timestamp - gracePeriod - 1
        );

        // mock rate feed 1
        mockRateFeed1 = new MockChainlinkAggregator();
        mockRateFeed1.setDecimals(18);

        // mock rate feed 2
        mockRateFeed2 = new MockChainlinkAggregator();
        mockRateFeed2.setDecimals(18);

        // mock price feed 1
        mockPriceFeed1 = new MockChainlinkAggregator();
        mockPriceFeed1.setDecimals(8);

        // deploy chainlink composite oracle provider
        address chainlinkOracleCompositeImplementation = address(
            new ChainlinkOracleComposite(
                AggregatorV3Interface(sequencerUptimeFeed), getAdmin()
            )
        );
        bytes memory data = abi.encodeCall(ChainlinkOracleComposite.initialize, ());
        ERC1967Proxy chainlinkOracleCompositeProxy =
            new ERC1967Proxy(chainlinkOracleCompositeImplementation, data);

        chainlinkOracleComposite =
            ChainlinkOracleComposite(address(chainlinkOracleCompositeProxy));

        wsteth = pWSTETH.asset();
    }

    function testChainlinkOracleComposite(
        uint256 rate1,
        uint256 rate2,
        uint256 price1,
        bool[3] memory inverts
    ) public {
        vm.startPrank(_testState.admin);

        rate1 = bound(rate1, 1e12, 100e18);
        rate2 = bound(rate2, 1e12, 100e18);
        price1 = bound(price1, 1, 1_000_000_000e8);

        mockRateFeed1.setRoundData(rate1, block.timestamp, block.timestamp);
        mockRateFeed2.setRoundData(rate2, block.timestamp, block.timestamp);
        mockPriceFeed1.setRoundData(price1, block.timestamp, block.timestamp);

        AggregatorV3Interface[3] memory feeds;
        // bool[3] memory inverts;
        uint256[3] memory stalePeriods;

        feeds[0] = mockRateFeed1;
        feeds[1] = mockRateFeed2;
        feeds[2] = mockPriceFeed1;
        stalePeriods[0] = 1 hours;
        stalePeriods[1] = 1 hours;
        stalePeriods[2] = 1 hours;

        // configure wsteth price
        chainlinkOracleComposite.setAssetConfig(wsteth, feeds, inverts, stalePeriods);

        chainlinkOracleComposite.getAssetConfig(wsteth);

        // get wsteth price to make sure it does not over flow
        uint256 wstethPrice = chainlinkOracleComposite.getPrice(wsteth);
        console.log(wstethPrice);
    }
}
