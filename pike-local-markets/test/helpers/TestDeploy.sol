// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {Timelock} from "@governance/Timelock.sol";
import {Factory} from "@factory/Factory.sol";
import {UpgradeableBeacon} from
    "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CannonDeploy} from "@helpers/TestDeployFactory.sol";
import {TestSetters} from "@helpers/TestSetters.sol";
import {DiamondCutFacet} from "@mocks/Diamond/facets/DiamondCutFacet.sol";
import {Diamond} from "@mocks/Diamond/Diamond.sol";
import {DiamondLoupeFacet} from "@mocks/Diamond/facets/DiamondLoupeFacet.sol";
import {strings} from "@mocks/Diamond/libraries/Strings.sol";
import {IDiamondCut} from "@mocks/Diamond/IDiamondCut.sol";
import {InitialModuleBundle} from "@modules/InitialModuleBundle.sol";
import {InitialModuleBeacon} from "@modules/InitialModuleBeacon.sol";
import {RBACModule, IRBAC} from "@modules/common/RBACModule.sol";
import {RiskEngineModule, IRiskEngine} from "@modules/riskEngine/RiskEngineModule.sol";
import {DoubleJumpRateModel} from "@modules/interestRateModel/DoubleJumpRateModel.sol";
import {PTokenModule, IPToken} from "@modules/pToken/PTokenModule.sol";
import {MockToken, MockReentrantToken} from "@mocks/MockToken.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract TestDeploy is TestSetters, CannonDeploy {
    using strings for *;

    bytes32 constant configurator_permission =
        0x434f4e464947555241544f520000000000000000000000000000000000000000;

    bytes32 constant owner_withdrawer =
        0x4f574e45525f5749544844524157455200000000000000000000000000000000;

    bytes32 constant emergency_withdrawer =
        0x454d455247454e43595f57495448445241574552000000000000000000000000;

    bytes32 constant protocol_owner =
        0x50524f544f434f4c5f4f574e4552000000000000000000000000000000000000;

    bytes32 constant supply_guard_permission =
        0x535550504c595f4341505f475541524449414e00000000000000000000000000;

    bytes32 constant borrow_guard_permission =
        0x424f52524f575f4341505f475541524449414e00000000000000000000000000;

    bytes32 constant pause_guard_permission =
        0x50415553455f475541524449414e000000000000000000000000000000000000;

    bytes32 constant reserve_manager_permission =
        0x524553455256455f4d414e414745520000000000000000000000000000000000;

    bytes32 constant reserve_withdrawer_permission =
        0x524553455256455f574954484452415745520000000000000000000000000000;

    uint256 ownerShare = 30e16; //30%
    uint256 configuratorShare = 20e16; //20%

    uint256 initialExchangeRate = 1e18;
    uint256 reserveFactor = 10e16;
    uint256 protocolSeizeShare = 1e16;
    uint256 borrowRateMax = 5e12;
    uint8 pTokenDecimals = 18;

    uint256 baseRate = 0;
    uint256 initialMultiplier = 0;
    uint256 jumpMultiplierPerYear1 = 6.111111e16;
    uint256 jumpMultiplierPerYear2 = 6e18;
    uint256 kink1 = 5e16;
    uint256 kink2 = 95e16;

    uint256 closeFactor = 50e16;
    uint256 liquidationIncentive = 1.08e18;

    function deployProtocol() public virtual {
        address oracle = address(new MockOracle());
        setOracle(oracle);

        deployRiskEngine();
    }

    function deployProtocolFactory() public virtual {
        runFactory();
        address oracleImpl = getAddress[keccak256("OracleEngine")];
        address oracle = address(new UpgradeableBeacon(oracleImpl, getAdmin()));
        setOracle(oracle);
        address riskEngine = getAddress[keccak256("reBeacon")];
        setRiskEngine(riskEngine);
        address timelock = deployTimelock();
        setTimelock(timelock);
        address pToken = getAddress[keccak256("pTokenBeacon")];
        setPToken("beacon", pToken);

        bytes memory factoryInit = abi.encodeCall(
            Factory.initialize, (getAdmin(), riskEngine, oracle, pToken, timelock)
        );

        Factory factory = new Factory();
        address factoryProxy = address(new ERC1967Proxy(address(factory), factoryInit));
        setFactory(factoryProxy);
    }

    function deployTimelock() internal returns (address) {
        address timelockImpl = address(new Timelock());
        return address(new UpgradeableBeacon(timelockImpl, getAdmin()));
    }

    function deployPToken(
        string memory name_,
        string memory symbol_,
        uint8 underlyingDecimals,
        uint256 price,
        uint256 colFactor,
        uint256 liqThreshold,
        function (string memory, string memory, uint8) internal returns (address)
            deployUnderlying
    ) internal virtual returns (address) {
        address underlying = deployUnderlying(name_, symbol_, underlyingDecimals);

        IRiskEngine re = IRiskEngine(getRiskEngine());
        initialExchangeRate = 2 * (10 ** (8 + underlyingDecimals));

        PTokenInitialization memory initData = PTokenInitialization({
            underlying: underlying,
            riskEngine: re,
            initialExchangeRate: initialExchangeRate,
            reserveFactor: reserveFactor,
            protocolSeizeShare: protocolSeizeShare,
            borrowRateMax: borrowRateMax,
            name: name_,
            symbol: symbol_,
            pTokenDecimals: pTokenDecimals
        });

        string[] memory pTokenFacets = new string[](4);
        pTokenFacets[0] = "InitialModuleBundle";
        pTokenFacets[1] = "DoubleJumpRateModel";
        pTokenFacets[2] = "PTokenModule";
        pTokenFacets[3] = "RBACModule";

        address[] memory pTokenModulesAddresses = new address[](4);
        pTokenModulesAddresses[0] = address(new InitialModuleBundle());
        pTokenModulesAddresses[1] = address(new DoubleJumpRateModel());
        pTokenModulesAddresses[2] = address(new PTokenModule());
        pTokenModulesAddresses[3] = address(new RBACModule());

        address _pToken = deployDiamond(pTokenFacets, pTokenModulesAddresses);
        setPToken(symbol_, _pToken);

        MockOracle(getOracle()).setPrice(_pToken, price, MockToken(underlying).decimals());

        InitialModuleBundle initialModuleBundle = InitialModuleBundle(_pToken);
        initialModuleBundle.initialize(getAdmin());

        vm.startPrank(getAdmin());
        PTokenModule pToken = PTokenModule(_pToken);
        pToken.initialize(
            initData.underlying,
            initData.riskEngine,
            initData.initialExchangeRate,
            initData.reserveFactor,
            initData.protocolSeizeShare,
            initData.borrowRateMax,
            initData.name,
            initData.symbol,
            initData.pTokenDecimals
        );

        IRBAC(address(re)).grantNestedPermission(
            configurator_permission, _pToken, getAdmin()
        );

        DoubleJumpRateModel interestRateModule = DoubleJumpRateModel(_pToken);
        interestRateModule.configureInterestRateModel(
            baseRate,
            initialMultiplier,
            jumpMultiplierPerYear1,
            jumpMultiplierPerYear2,
            kink1,
            kink2
        );

        re.supportMarket(IPToken(_pToken));
        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(colFactor, liqThreshold, liquidationIncentive);
        re.configureMarket(IPToken(_pToken), config);

        assertEq(re.collateralFactor(0, IPToken(_pToken)), colFactor);
        assertEq(re.liquidationThreshold(0, IPToken(_pToken)), liqThreshold);

        IPToken[] memory markets = new IPToken[](1);
        markets[0] = IPToken(_pToken);

        uint256[] memory caps = new uint256[](1);
        caps[0] = type(uint256).max;

        re.setMarketBorrowCaps(markets, caps);
        re.setMarketSupplyCaps(markets, caps);

        assertEq(re.supplyCap(address(markets[0])), caps[0]);
        assertEq(re.borrowCap(address(markets[0])), caps[0]);

        re.setCloseFactor(_pToken, closeFactor);

        assertEq(re.liquidationIncentive(0, _pToken), liquidationIncentive);
        assertEq(re.closeFactor(_pToken), closeFactor);

        vm.stopPrank();

        assertEq(IPToken(_pToken).decimals(), pTokenDecimals);
        assertEq(
            keccak256(abi.encodePacked(IPToken(_pToken).symbol())),
            keccak256(abi.encodePacked(initData.symbol))
        );
        assertEq(IPToken(_pToken).borrowIndex(), 1e18);
        assertEq(IPToken(_pToken).initialExchangeRate(), initialExchangeRate);

        return _pToken;
    }

    function deployRiskEngine() internal virtual returns (address) {
        string[] memory riskEngineModulesFacets = new string[](3);
        riskEngineModulesFacets[0] = "InitialModuleBundle";
        riskEngineModulesFacets[1] = "RBACModule";
        riskEngineModulesFacets[2] = "RiskEngineModule";

        address[] memory riskEngineModulesAddresses = new address[](3);
        riskEngineModulesAddresses[0] = address(new InitialModuleBundle());
        riskEngineModulesAddresses[1] = address(new RBACModule());
        riskEngineModulesAddresses[2] = address(new RiskEngineModule());

        address riskEngine =
            deployDiamond(riskEngineModulesFacets, riskEngineModulesAddresses);
        setRiskEngine(riskEngine);

        InitialModuleBundle initialModuleBundle = InitialModuleBundle(riskEngine);
        initialModuleBundle.initialize(getAdmin());

        vm.startPrank(getAdmin());

        IRBAC(riskEngine).grantPermission(configurator_permission, getAdmin());
        IRBAC(riskEngine).grantPermission(pause_guard_permission, getAdmin());
        IRBAC(riskEngine).grantPermission(protocol_owner, getAdmin());
        IRBAC(riskEngine).grantPermission(supply_guard_permission, getAdmin());
        IRBAC(riskEngine).grantPermission(borrow_guard_permission, getAdmin());

        IRBAC(riskEngine).grantPermission(reserve_manager_permission, getAdmin());
        IRBAC(riskEngine).grantPermission(reserve_withdrawer_permission, getAdmin());
        IRBAC(riskEngine).grantPermission(emergency_withdrawer, getAdmin());
        IRBAC(riskEngine).grantPermission(owner_withdrawer, getAdmin());

        IRiskEngine(riskEngine).setOracle(getOracle());
        IRiskEngine(riskEngine).setReserveShares(30e16, 20e16);

        vm.stopPrank();

        return riskEngine;
    }

    function deployDiamond(string[] memory facets, address[] memory facetAddresses)
        internal
        returns (address)
    {
        vm.startPrank(getAdmin());
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

        DiamondCutFacet diamond =
            DiamondCutFacet(address(new Diamond(getAdmin(), address(diamondCutFacet))));

        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();

        bytes4[] memory diamondLoupeFacetSelectors =
            generateSelectors("DiamondLoupeFacet");

        DiamondCutFacet.FacetCut[] memory diamondLoupeFacetCut =
            new DiamondCutFacet.FacetCut[](facets.length + 1);
        diamondLoupeFacetCut[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: diamondLoupeFacetSelectors
        });

        for (uint256 i = 0; i < facets.length; i++) {
            bytes4[] memory selectors = generateSelectors(facets[i]);
            diamondLoupeFacetCut[i + 1] = IDiamondCut.FacetCut({
                facetAddress: facetAddresses[i],
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        diamond.diamondCut(diamondLoupeFacetCut, address(0), "");
        vm.stopPrank();

        return address(diamond);
    }

    function generateSelectors(string memory _facetName)
        internal
        returns (bytes4[] memory)
    {
        string[] memory cmd = new string[](4);
        cmd[0] = "forge";
        cmd[1] = "inspect";
        cmd[2] = _facetName;
        cmd[3] = "methods";
        string memory st = string(vm.ffi(cmd));

        strings.slice memory s = st.toSlice();
        strings.slice memory nl = "\n".toSlice();

        // Skip traces
        while (s.contains("TRACE".toSlice())) {
            s.split(nl);
        }

        // Skip to the actual data
        while (!s.contains("+=".toSlice())) {
            s.split(nl);
        }
        s.split(nl); // Skip the separator line

        // Count valid lines
        uint256 count = 0;
        strings.slice memory tempSlice = s.copy();
        while (!tempSlice.empty()) {
            strings.slice memory line = tempSlice.split(nl);
            if (
                line.contains("|".toSlice()) && !line.contains("+--".toSlice())
                    && !line.contains("Identifier".toSlice())
            ) {
                count++;
            }
        }

        require(count > 0, "No selectors found");
        bytes4[] memory selectors = new bytes4[](count);

        // Extract selectors
        uint256 i = 0;
        while (!s.empty() && i < count) {
            strings.slice memory line = s.split(nl);
            if (
                !line.contains("|".toSlice()) || line.contains("+--".toSlice())
                    || line.contains("Identifier".toSlice())
            ) continue;

            // Get the last column (selector)
            strings.slice memory parts = line.copy();
            strings.slice memory lastPart;
            while (parts.contains("|".toSlice())) {
                lastPart = parts.split("|".toSlice());
            }

            // Clean up whitespace
            strings.slice memory space = " ".toSlice();
            while (lastPart.startsWith(space)) {
                lastPart.split(space);
            }
            while (lastPart.endsWith(space)) {
                lastPart = lastPart.until(space);
            }

            string memory selStr = lastPart.toString();
            if (bytes(selStr).length > 0) {
                // Convert hex string to bytes4
                bytes memory b = bytes(selStr);
                require(b.length == 8, "Invalid selector length");

                uint32 raw = 0;
                for (uint32 j = 0; j < 8; j++) {
                    uint8 digit = uint8(b[j]);
                    // Convert hex char to value
                    if (digit >= 48 && digit <= 57) digit -= 48; // 0-9

                    else if (digit >= 97 && digit <= 102) digit = digit - 97 + 10; // a-f

                    else if (digit >= 65 && digit <= 70) digit = digit - 65 + 10; // A-F

                    else revert("Invalid hex character");

                    raw |= uint32(digit) << ((7 - j) * 4);
                }

                selectors[i] = bytes4(raw);
                i++;
            }
        }

        require(i == count, "Selector count mismatch");
        return selectors;
    }

    function deployMockToken(string memory name_, string memory symbol_, uint8 decimals_)
        internal
        returns (address)
    {
        return address(new MockToken(name_, symbol_, decimals_));
    }

    function deployMockReentrantToken(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) internal returns (address) {
        return address(new MockReentrantToken(name_, symbol_, decimals_));
    }
}
