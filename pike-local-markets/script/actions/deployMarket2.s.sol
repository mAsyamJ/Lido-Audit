pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {Timelock} from "@governance/Timelock.sol";
import {MockTestToken} from "test/mocks/MockToken.sol";
import {MockProvider} from "test/mocks/MockOracle.sol";

import {Config, console} from "../Config.sol";

contract Market is Config {
    string PATH;

    IFactory factory;

    IPToken pUSDC;
    IPToken pCBBTC;
    IPToken pLBTC;

    IRiskEngine re;
    IOracleEngine oe;
    Timelock tm;
    MockProvider mp;

    constructor() Config() {
        PATH = "";
    }

    function run() public payable {
        setUp();
        uint256 selectedFork = 1;
        vm.createSelectFork(vm.envString(rpcs[selectedFork]));
        forks[selectedFork] = vm.activeFork();

        vm.startBroadcast(adminPrivateKey);

        address usdc = 0xaFB14cF9A468CDb13739bf1268D0f9537478D04b;
        address cbBTC =
            address(new MockTestToken("Coinbase Wrapped BTC", "cbBTC", 8, 5e8));
        address LBTC =
            address(new MockTestToken("Lombard Staked Bitcoin", "LBTC", 8, 5e8));
        mp = MockProvider(0x8737137431c31AD3533CBC14a399DD67E9f27d5d);
        mp.setPrice(usdc, 1e6, 6);
        mp.setPrice(cbBTC, 100_000e6, 8);
        mp.setPrice(LBTC, 100_000e6, 8);

        factory = IFactory(0x82072C90aacbb62dbD7A0EbAAe3b3e5D7d8cEEEA);

        uint256 protocolId = factory.protocolCount();
        IFactory.PTokenSetup memory pUSDCSetup = IFactory.PTokenSetup(
            protocolId, usdc, 1e18, 1e16, 2e16, 1e18, "pike usdc", "pUSDC", 8
        );
        IFactory.PTokenSetup memory pCBBTCSetup = IFactory.PTokenSetup(
            protocolId, cbBTC, 1e18, 1e16, 2e16, 1e18, "pike cbBTC", "pCBBTC", 8
        );
        IFactory.PTokenSetup memory pLBTCSetup = IFactory.PTokenSetup(
            protocolId, LBTC, 1e18, 1e16, 2e16, 1e18, "pike LBTC", "pLBTC", 8
        );

        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(72.5e16, 82.5e16, 102e16);

        // step 1 get protocol info
        console.log("deployed protocol: %s", protocolId);

        oe = IOracleEngine(factory.getProtocolInfo(protocolId).oracleEngine);
        re = IRiskEngine(factory.getProtocolInfo(protocolId).riskEngine);
        tm = Timelock(payable(factory.getProtocolInfo(protocolId).timelock));

        console.log("deployed risk engine: %s", address(re));
        console.log("deployed oracle engine: %s", address(oe));
        console.log("deployed timelock: %s", address(tm));

        // step 2 deploy pTokens
        console.log("deploying %s", pUSDCSetup.name);
        tm.emergencyExecute(
            address(factory),
            0,
            abi.encodeWithSelector(factory.deployMarket.selector, pUSDCSetup)
        );
        pUSDC = IPToken(factory.getMarket(protocolId, 0));
        console.log("deployed: %s", address(pUSDC));

        console.log("deploying: %s", pCBBTCSetup.name);
        tm.emergencyExecute(
            address(factory),
            0,
            abi.encodeWithSelector(factory.deployMarket.selector, pCBBTCSetup)
        );
        pCBBTC = IPToken(factory.getMarket(protocolId, 1));
        console.log("deployed: %s", address(pCBBTC));

        console.log("deploying: %s", pLBTCSetup.name);
        tm.emergencyExecute(
            address(factory),
            0,
            abi.encodeWithSelector(factory.deployMarket.selector, pLBTCSetup)
        );
        pLBTC = IPToken(factory.getMarket(protocolId, 2));
        console.log("deployed: %s", address(pLBTC));

        // step 3 set oracle engine data providers
        IPToken[] memory markets = new IPToken[](3);
        markets[0] = pUSDC;
        markets[1] = pCBBTC;
        markets[2] = pLBTC;

        uint256[] memory caps = new uint256[](3);
        caps[0] = type(uint256).max;
        caps[1] = type(uint256).max;
        caps[2] = type(uint256).max;

        tm.emergencyExecute(
            address(oe),
            0,
            abi.encodeWithSelector(
                oe.setAssetConfig.selector, pUSDC.asset(), address(mp), address(0), 0, 0
            )
        );
        tm.emergencyExecute(
            address(oe),
            0,
            abi.encodeWithSelector(
                oe.setAssetConfig.selector, pCBBTC.asset(), address(mp), address(0), 0, 0
            )
        );
        tm.emergencyExecute(
            address(oe),
            0,
            abi.encodeWithSelector(
                oe.setAssetConfig.selector, pLBTC.asset(), address(mp), address(0), 0, 0
            )
        );
        console.log(
            "oracle set for %s with price: %s",
            pUSDCSetup.name,
            oe.getUnderlyingPrice(pUSDC)
        );
        console.log(
            "oracle set for %s with price: %s",
            pCBBTCSetup.name,
            oe.getUnderlyingPrice(pCBBTC)
        );
        console.log(
            "oracle set for %s with price: %s",
            pLBTCSetup.name,
            oe.getUnderlyingPrice(pLBTC)
        );

        // step 4 set risk engine config for pTokens
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.configureMarket.selector, pUSDC, config)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.configureMarket.selector, pCBBTC, config)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.configureMarket.selector, pLBTC, config)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setCloseFactor.selector, address(pUSDC), 50e16)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setCloseFactor.selector, address(pCBBTC), 50e16)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setCloseFactor.selector, address(pLBTC), 50e16)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setMarketSupplyCaps.selector, markets, caps)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setMarketBorrowCaps.selector, markets, caps)
        );
        console.log("Risk Engine configured");

        // step 5 set pToken config for IRM
        tm.emergencyExecute(
            address(pUSDC),
            0,
            abi.encodeWithSelector(
                IDoubleJumpRateModel.configureInterestRateModel.selector,
                0,
                0,
                6.111111e16,
                6e18,
                5e16,
                95e16
            )
        );
        tm.emergencyExecute(
            address(pCBBTC),
            0,
            abi.encodeWithSelector(
                IDoubleJumpRateModel.configureInterestRateModel.selector,
                0,
                0,
                6.111111e16,
                6e18,
                5e16,
                95e16
            )
        );
        tm.emergencyExecute(
            address(pLBTC),
            0,
            abi.encodeWithSelector(
                IDoubleJumpRateModel.configureInterestRateModel.selector,
                0,
                0,
                6.111111e16,
                6e18,
                5e16,
                95e16
            )
        );
        console.log("IRM configured");
    }

    function getAddress(string memory key, string memory name)
        internal
        view
        returns (address)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, PATH, name, ".json");
        bytes memory addr = vm.parseJson(vm.readFile(path), key);
        return abi.decode(addr, (address));
    }
}
