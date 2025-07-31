pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";
import {IRBAC} from "@modules/common/RBACModule.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalRiskEngine is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;

    MockOracle mockOracle;

    IRiskEngine re;

    function setUp() public {
        setDebug(false);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockToken);
        deployPToken("pike-weth", "pWETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken);

        /// eth price = 2000$, usdc price = 1$
        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());

        //inital mint
        doInitialMint(pUSDC);
        doInitialMint(pWETH);
    }

    function testPauseMint_Success() public {
        address user1 = makeAddr("user1");

        vm.prank(getAdmin());
        re.setMintPaused(pUSDC, true);

        // "MintPaused()" selector
        doDepositRevert(
            user1, user1, address(pUSDC), 2000e6, abi.encodePacked(bytes4(0xd7d248ba))
        );
    }

    function testPauseBorrow_Success() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        vm.prank(getAdmin());
        re.setBorrowPaused(pWETH, true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        // "BorrowPaused()" selector
        doBorrowRevert(
            user1, user1, address(pWETH), 0.745e18, abi.encodePacked(bytes4(0x12b0cb46))
        );
    }

    function testPauseTransfer_Success() public {
        address user1 = makeAddr("user1");
        address receiver = makeAddr("receiver");

        vm.prank(getAdmin());
        re.setTransferPaused(true);

        doDeposit(user1, user1, address(pUSDC), 2000e6);
        // "TransferPaused()" selector
        doTransferRevert(
            user1,
            user1,
            receiver,
            address(pUSDC),
            2000e6,
            abi.encodePacked(bytes4(0xcd1fda9f))
        );
    }

    function testPauseSeize_Success() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        vm.prank(getAdmin());
        re.setSeizePaused(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);
        // "SeizePaused()" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0x0fe80ef6))
        });

        doLiquidate(lp);
    }

    function testBorrow_FailIfNotEntered() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        vm.prank(user1);
        re.exitMarket(address(pUSDC));

        assertEq(re.getAssetsIn(user1).length, 0, "assets are not empty");
        assertEq(re.checkCollateralMembership(user1, pUSDC), false, "still in market");
        // "BorrowRiskEngineRejection(3)" selector
        doBorrowRevert(
            user1,
            user1,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xcd617e38), uint256(3))
        );
    }

    function testBorrow_FailIfCapReached() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        uint256 borrowAmount = 0.745e18;

        IPToken[] memory markets = new IPToken[](1);
        markets[0] = pWETH;

        uint256[] memory caps = new uint256[](1);
        caps[0] = borrowAmount - 1;

        vm.prank(getAdmin());
        re.setMarketBorrowCaps(markets, caps);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        // "BorrowRiskEngineRejection(8)" selector
        doBorrowRevert(
            user1,
            user1,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xcd617e38), uint256(8))
        );
    }

    function testMint_FailIfCapReached() public {
        address user1 = makeAddr("user1");
        uint256 mintAmount = 2000e18;

        IPToken[] memory markets = new IPToken[](1);
        markets[0] = pWETH;

        uint256[] memory caps = new uint256[](1);
        caps[0] = mintAmount - 1;

        changeList(address(pUSDC), false);

        // max deposit 0 for unlisted
        assertEq(0, pUSDC.maxDeposit(address(0)), "maxDeposit does not match unlisted");

        // max deposit uint256 max by default
        assertEq(
            type(uint256).max,
            pWETH.maxDeposit(address(0)),
            "maxDeposit does not uint256 max"
        );

        vm.prank(getAdmin());
        re.setMarketSupplyCaps(markets, caps);
        uint256 cap = caps[0] - (5000 * pWETH.initialExchangeRate() / ONE_MANTISSA);
        // applied cap - initial mint amount
        assertEq(cap, pWETH.maxDeposit(address(0)), "maxDeposit does not match cap");
        assertApproxEqRel(
            cap,
            pWETH.maxMint(address(0)) * pWETH.exchangeRateCurrent() / ONE_MANTISSA,
            1e5,
            "maxMint does not match cap"
        );

        // "BorrowRiskEngineRejection(7)" selector
        doDepositRevert(
            user1,
            user1,
            address(pWETH),
            mintAmount,
            abi.encodePacked(bytes4(0x1d3413fb), uint256(7))
        );
    }

    function testGetMarkets() public view {
        IPToken[] memory markets = re.getAllMarkets();

        assertEq(address(pUSDC), address(markets[0]));
        assertEq(address(pWETH), address(markets[1]));
    }

    function testDeprecateMarket() public {
        vm.startPrank(getAdmin());
        pUSDC.setReserveFactor(1e18);

        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(0, 0, 108e16);
        re.configureMarket(pUSDC, config);
        re.setBorrowPaused(pUSDC, true);

        assertEq(re.isDeprecated(pUSDC), true, "not deprecated");
    }

    function testSetCF_FailIfNotListed() public {
        vm.startPrank(getAdmin());

        changeList(address(pUSDC), false);

        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(0, 0, 108e16);
        // "MarketNotListed()" selector
        vm.expectRevert(bytes4(0x69609fc6));
        re.configureMarket(IPToken(pUSDC), config);
    }

    function testSetCF_FailIfNotInRange() public {
        vm.startPrank(getAdmin());

        // "InvalidCloseFactor()" selector
        vm.expectRevert(bytes4(0xee0bdbdf));
        re.setCloseFactor(address(pUSDC), 2e18);
    }

    function testSetCF_FailIfInvalidCF() public {
        vm.startPrank(getAdmin());

        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(1e18, 0, 108e16);
        // "InvalidCollateralFactor()" selector
        vm.expectRevert(bytes4(0xbc8b2b40));
        re.configureMarket(pUSDC, config);

        config = IRiskEngine.BaseConfiguration(0, 1e18 + 1, 108e16);
        // "InvalidLiquidationThreshold()" selector
        vm.expectRevert(bytes4(0x3e51d2c0));
        re.configureMarket(pUSDC, config);

        config = IRiskEngine.BaseConfiguration(0.8e18, 0.7e18, 108e16);
        // "InvalidLiquidationThreshold()" selector
        vm.expectRevert(bytes4(0x3e51d2c0));
        re.configureMarket(pUSDC, config);

        config = IRiskEngine.BaseConfiguration(0.7e18, 0.8e18, 10e16);
        // "InvalidIncentiveThreshold()" selector
        vm.expectRevert(bytes4(0x37fbf6a6));
        re.configureMarket(pUSDC, config);
    }

    function testSetOracle_FailIfAddressIsZero() public {
        vm.prank(getAdmin());

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        re.setOracle(address(0));
    }

    function testSupportMarket_FailIfAlreadyListedOrUnsupported() public {
        vm.startPrank(getAdmin());

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        re.supportMarket(IPToken(address(0)));

        // "AlreadyListed()" selector
        vm.expectRevert(bytes4(0xa3d582ec));
        re.supportMarket(pUSDC);

        changeList(address(pUSDC), false);

        // "AlreadyListed()" selector
        vm.expectRevert(bytes4(0xa3d582ec));
        re.supportMarket(pUSDC);
    }

    function testSetCaps_FailIfNoParity() public {
        vm.startPrank(getAdmin());

        IPToken[] memory pTokens = new IPToken[](0);
        uint256[] memory caps = new uint256[](0);

        // "NoArrayParity()" selector
        vm.expectRevert(bytes4(0x266c51bb));
        re.setMarketBorrowCaps(pTokens, caps);

        // "NoArrayParity()" selector
        vm.expectRevert(bytes4(0x266c51bb));
        re.setMarketSupplyCaps(pTokens, caps);
    }

    function testSetPause_FailIfNotListed() public {
        vm.startPrank(getAdmin());

        // "MarketNotListed()" selector
        vm.expectRevert(bytes4(0x69609fc6));
        re.setMintPaused(IPToken(address(0)), true);

        // "MarketNotListed()" selector
        vm.expectRevert(bytes4(0x69609fc6));
        re.setBorrowPaused(IPToken(address(0)), true);
    }

    function testExit_FailIfPriceZero() public {
        address user1 = makeAddr("user1");

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        mockOracle.setPrice(address(pUSDC), 0, 18);

        vm.prank(user1);
        // "ExitMarketRedeemRejection(uint256)" selector
        vm.expectRevert(abi.encodePacked(bytes4(0xf34eff40), uint256(5)));
        re.exitMarket(address(pUSDC));
    }

    function testExit_FailIfNotListed() public {
        address user1 = makeAddr("user1");

        changeList(address(pWETH), false);

        vm.prank(user1);
        // "ExitMarketRedeemRejection(uint256)" selector
        vm.expectRevert(abi.encodePacked(bytes4(0xf34eff40), uint256(4)));
        re.exitMarket(address(pWETH));
    }

    function testExit_SucessWithoutEnter() public {
        address user1 = makeAddr("user1");

        doDeposit(user1, user1, address(pUSDC), 2000e6);
        vm.prank(user1);
        re.exitMarket(address(pUSDC));
    }

    function testDelegate_Fail() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        vm.startPrank(user1);
        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        re.updateDelegate(address(0), true);

        re.updateDelegate(user2, true);

        // "DelegationStatusUnchanged()" selector
        vm.expectRevert(bytes4(0xdb6c2c83));
        re.updateDelegate(user2, true);
    }

    function testBorrowAllowed_Fail() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        mockOracle.setPrice(address(pWETH), 0, 18);

        // "BorrowRiskEngineRejection(uint256)" selector
        doBorrowRevert(
            user1,
            user1,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xcd617e38), uint256(5))
        );

        mockOracle.setPrice(address(pWETH), 2000e6, 18);
        mockOracle.setPrice(address(pUSDC), 0, 18);

        // "BorrowRiskEngineRejection(uint256)" selector
        doBorrowRevert(
            user1,
            user1,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xcd617e38), uint256(5))
        );

        changeList(address(pWETH), false);

        // "BorrowRiskEngineRejection(uint256)" selector
        doBorrowRevert(
            user1,
            user1,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xcd617e38), uint256(4))
        );

        changeList(user1, true);

        vm.prank(address(1));
        // "SenderNotPToken()" selector
        vm.expectRevert(bytes4(0xe6c91dd9));
        re.borrowAllowed(user1, user1, 0);
    }

    function testMintAllowed_FailIfNotListed() public {
        address user1 = makeAddr("user1");

        changeList(address(pUSDC), false);

        // "MintRiskEngineRejection(uint256)" selector
        doDepositRevert(
            user1,
            user1,
            address(pUSDC),
            2000e6,
            abi.encodePacked(bytes4(0x1d3413fb), uint256(4))
        );
    }

    function testLiquidateAllowed_Fail() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // "LiquidateRiskEngineRejection(uint256)" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 726e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0xd1192049), uint256(2))
        });
        doLiquidate(lp);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);
        // "LiquidateRiskEngineRejection(uint256)" selector
        lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 726e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0xd1192049), uint256(6))
        });
        doLiquidate(lp);

        // deprecate pUSDC
        vm.startPrank(getAdmin());
        pUSDC.setReserveFactor(1e18);
        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(0, 0, 108e16);
        re.configureMarket(pUSDC, config);
        re.setBorrowPaused(pUSDC, true);
        vm.stopPrank();

        // "RepayMoreThanBorrowed()" selector
        lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 1451e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0x6b48cf42))
        });
        doLiquidate(lp);
    }

    function testSeizeAllowed_Fail() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);
        vm.prank(depositor);
        re.exitMarket(address(pUSDC));

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        address mockRE = deployRiskEngine();
        vm.prank(getAdmin());
        // change risk engine
        setRiskEngineSlot(address(pWETH), mockRE);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);
        // "LiquidateSeizeRiskEngineRejection(uint256)" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0x995a5edc), uint256(4))
        });
        doLiquidate(lp);

        vm.startPrank(getAdmin());
        IRiskEngine(mockRE).supportMarket(pWETH);
        IRiskEngine(mockRE).supportMarket(pUSDC);
        vm.stopPrank();

        // "LiquidateSeizeRiskEngineRejection(uint256)" selector
        lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0x995a5edc), uint256(1))
        });
        doLiquidate(lp);
    }

    function testAddToMarket_Fail() public {
        address user1 = makeAddr("user1");

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        enterMarket(user1, address(pUSDC));

        address[] memory markets = new address[](1);
        markets[0] = address(0);

        vm.prank(user1);
        uint256[] memory results = re.enterMarkets(markets);
        // market not listed error code = 4
        assertEq(results[0], 4);
    }
}
