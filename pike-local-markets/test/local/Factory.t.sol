pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";
import {Factory, IFactory} from "@factory/Factory.sol";
import {IRBAC} from "@modules/common/RBACModule.sol";
import {Timelock} from "@governance/Timelock.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IOwnable} from "@interfaces/IOwnable.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {OracleEngine} from "@oracles/OracleEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalFactory is TestLocal {
    address governor;
    address guardian;
    address underlyingToken;
    IPToken pUSDC;
    IPToken pWETH;
    IPToken pSTETH;

    MockOracle mockOracle;
    OracleEngine oe;
    Timelock governorTL;

    Factory factory;

    IRiskEngine re;

    IFactory.PTokenSetup public ptokenSetup;

    function setUp() public {
        setDebug(false);
        setAdmin(0x8da29648bd3bbef6f0cc1C0b3a9a286ED14E2963);
        initFactory();

        underlyingToken = deployMockToken("mockToken", "MKT", 18);
        ptokenSetup = IFactory.PTokenSetup(
            1,
            underlyingToken,
            initialExchangeRate,
            reserveFactor,
            protocolSeizeShare,
            borrowRateMax,
            "MockPToken",
            "MPT",
            8
        );

        governor = makeAddr("Governor");
        guardian = makeAddr("Guardian");

        factory = getFactory();

        vm.startPrank(getAdmin());

        (address riskEngine, address oracleEngine, address payable governorTimelock) =
            factory.deployProtocol(governor, guardian, ownerShare, configuratorShare);
        re = IRiskEngine(riskEngine);
        oe = OracleEngine(oracleEngine);
        governorTL = Timelock(governorTimelock);
        vm.stopPrank();

        assertEq(getOracle(), factory.oracleEngineBeacon());
        assertEq(address(getRiskEngine()), factory.riskEngineBeacon());
        assertEq(address(getPToken("beacon")), factory.pTokenBeacon());
        assertEq(address(getTimelock()), factory.timelockBeacon());
    }

    function testDeployedProtocol_Success() public view {
        assertEq(governorTL.hasRole(governorTL.PROPOSER_ROLE(), governor), true);
        assertEq(governorTL.hasRole(governorTL.CANCELLER_ROLE(), governor), true);
        assertEq(governorTL.hasRole(governorTL.EMERGENCY_GUARDIAN_ROLE(), guardian), true);
        assertEq(factory.protocolCount(), 1);
        assertEq(factory.owner(), getAdmin());
        Factory.ProtocolInfo memory $ = factory.getProtocolInfo(1);
        assertEq($.protocolId, 1);
        assertEq($.initialGovernor, governor);
        assertEq($.riskEngine, address(re));
        assertEq($.oracleEngine, address(oe));
        assertEq($.timelock, address(governorTL));
        assertEq($.protocolOwner, getAdmin());
        assertEq(re.oracle(), address(oe));
    }

    function testDeployedProtocol_FailIfNotOwner() public {
        vm.startPrank(governor);
        vm.expectRevert();
        factory.deployProtocol(governor, guardian, ownerShare, configuratorShare);
        vm.stopPrank();
    }

    function testDeployedPToken_FailIfNotOwner() public {
        vm.startPrank(governor);
        vm.expectRevert();
        factory.deployMarket(ptokenSetup);
        vm.stopPrank();

        vm.startPrank(getAdmin());

        uint256[] memory values = new uint256[](2);
        address[] memory targets = new address[](2);
        targets[0] = address(factory);
        targets[1] = address(factory);
        bytes[] memory payloads = new bytes[](2);

        payloads[0] = abi.encodeCall(factory.deployMarket, (ptokenSetup));
        payloads[1] = abi.encodeCall(factory.deployMarket, (ptokenSetup));

        vm.expectRevert();
        governorTL.emergencyExecute(targets[0], values[0], payloads[0]);

        vm.expectRevert();
        governorTL.emergencyExecuteBatch(targets, values, payloads);

        vm.stopPrank();
    }

    function testDeployedPToken_Success() public {
        vm.startPrank(guardian);
        uint256[] memory values = new uint256[](2);
        address[] memory targets = new address[](2);
        targets[0] = address(factory);
        targets[1] = address(factory);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(factory.deployMarket, (ptokenSetup));
        payloads[1] = abi.encodeCall(factory.deployMarket, (ptokenSetup));

        governorTL.emergencyExecute(targets[0], values[0], payloads[0]);
        governorTL.emergencyExecuteBatch(targets, values, payloads);
        vm.stopPrank();

        address pToken = factory.getMarket(1, 0);
        IPToken[] memory pTokens = re.getAllMarkets();
        Factory.ProtocolInfo memory $ = factory.getProtocolInfo(1);

        assertEq(address(pTokens[0]), pToken);
        assertEq(IOwnable(pToken).owner(), getAdmin());
        assertEq(IPToken(pToken).decimals(), 8);
        assertEq(IPToken(pToken).asset(), underlyingToken);
        assertEq($.numOfMarkets, 3);
    }

    function testTimelock_FailIfNoArrayParity() public {
        vm.startPrank(guardian);
        uint256[] memory values = new uint256[](1);
        address[] memory targets = new address[](2);
        targets[0] = address(factory);
        targets[1] = address(factory);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeCall(factory.deployMarket, (ptokenSetup));
        payloads[1] = abi.encodeCall(factory.deployMarket, (ptokenSetup));

        vm.expectRevert();
        governorTL.emergencyExecuteBatch(targets, values, payloads);
        vm.stopPrank();
    }
}
