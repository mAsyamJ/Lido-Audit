pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";
import {RiskEngineModule} from "@modules/riskEngine/RiskEngineModule.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalPToken is TestLocal {
    using stdStorage for StdStorage;

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

        //initail mint exceptioin case
        doInitialMintRevert(pWETH);
        //inital mint
        doInitialMint(pUSDC);
        doInitialMint(pWETH);
    }

    function testInitialize_FailIfAlreadyInitializedOrZeroAddress() public {
        vm.prank(getAdmin());

        // "AlreadyInitialized()" selector
        vm.expectRevert(bytes4(0x0dc149f0));
        PTokenModule(address(pUSDC)).initialize(
            address(0), IRiskEngine(address(0)), 0, 0, 0, 0, "", "", 0
        );
    }

    function testInitialize_FailIWithZeroValues() public {
        address pToken = address(new PTokenModule());
        // owner slot
        bytes32 slot = 0x74d6be38627e7912e34c50c5cbc5a4826c01ce9f17c41aaeea1b0611189c7000;
        vm.store(pToken, slot, bytes32(abi.encode(getAdmin())));

        vm.startPrank(getAdmin());
        // "ZeroValue()" selector
        vm.expectRevert(bytes4(0x7c946ed7));
        PTokenModule(pToken).initialize(
            address(0), IRiskEngine(address(0)), 0, 0, 0, 0, "", "", 0
        );

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        PTokenModule(pToken).initialize(
            address(0), IRiskEngine(address(0)), 1, 1, 1, 1, "", "", 0
        );

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        PTokenModule(pToken).initialize(
            address(1), IRiskEngine(address(0)), 1, 1, 1, 1, "", "", 0
        );

        vm.stopPrank();
    }

    function testAutoEnableCollateral() public {
        vm.prank(getAdmin());

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        assert(!re.checkCollateralMembership(user1, pUSDC));
        assert(!re.checkCollateralMembership(user2, pUSDC));

        doDeposit(user1, user1, address(pUSDC), 2000e6);

        // enable collateral with third party deposit
        doDeposit(user1, user2, address(pUSDC), 2000e6);

        /// should enable as collateral for iniital deposit
        assert(re.checkCollateralMembership(user1, pUSDC));
        assert(re.checkCollateralMembership(user2, pUSDC));
    }

    function testSetBorrowRateMax_Success() public {
        vm.prank(getAdmin());

        uint256 newBorrowRateMax = 2e6;
        pUSDC.setBorrowRateMax(newBorrowRateMax);

        assertEq(newBorrowRateMax, pUSDC.borrowRateMaxMantissa());
    }

    function testSweep_FailIfUnderlying() public {
        IERC20 underlying = IERC20(pUSDC.asset());
        vm.prank(getAdmin());
        // "SweepNotAllowed()" selector
        vm.expectRevert(bytes4(0x00b5509b));
        pUSDC.sweepToken(underlying);
    }

    function testSetProtocolShare_FailIfNotInRange() public {
        vm.startPrank(getAdmin());

        // "SetProtocolSeizeShareBoundsCheck()" selector
        vm.expectRevert(bytes4(0x5dc64e16));
        pUSDC.setProtocolSeizeShare(1e18);
    }

    function testTransfer_FailIfReceiverIsZero() public {
        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        pUSDC.transfer(address(0), 0);

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        pUSDC.transferFrom(address(0), address(0), 0);
    }

    function testRedeem_FailIfReceiverIsZero() public {
        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        pUSDC.redeem(0, address(0), address(0));

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        pUSDC.withdraw(0, address(0), address(0));
    }

    function testMintBehalfOf_FailIfAddressIsZero() public {
        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        pUSDC.deposit(0, address(0));

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        pUSDC.mint(0, address(0));
    }

    function testLiquidateBorrow_FailIfPTokenCollateralIsInvalid() public {
        address pToken = address(new PTokenModule());

        // "LiquidateAccrueCollateralInterestFailed()" selector
        vm.expectRevert(bytes4(0x181b94c8));
        pUSDC.liquidateBorrow(address(0), 0, IPToken(pToken));
    }

    function testApprove_FailIfAddressZero() public {
        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        pUSDC.approve(address(0), 0);
    }

    function testAccrueInterest_ReturnIfBorrowRateMaxMantissaReached() public {
        address user1 = makeAddr("user1");
        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pUSDC), 1000e6);

        // borrowRateMaxMantissa slot
        bytes32 slot = 0x0be5863c0c782626615eed72fc4c521bcfabebe439cbc2683e49afadb49a0d07;
        vm.store(address(pUSDC), slot, bytes32(0));

        //skip time
        skip(1);

        uint256 prevIndex = pUSDC.borrowIndex();
        pUSDC.accrueInterest();
        assertEq(prevIndex, pUSDC.borrowIndex());

        // "MintFreshnessCheck()" selector
        doDepositRevert(
            user1, user1, address(pUSDC), 1000e6, abi.encodePacked(bytes4(0x38d88597))
        );

        // "RedeemFreshnessCheck()" selector
        doWithdrawRevert(
            user1, user1, address(pUSDC), 100, abi.encodePacked(bytes4(0x97b5cfcd))
        );

        // "BorrowFreshnessCheck()" selector
        doBorrowRevert(
            user1, user1, address(pUSDC), 100, abi.encodePacked(bytes4(0x3a363184))
        );

        // "RepayBorrowFreshnessCheck()" selector
        doRepayRevert(
            user1, user1, address(pUSDC), 100, abi.encodePacked(bytes4(0xc9021e2f))
        );
    }

    function testRedeem_FailIfNotAllowed() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        uint256 liquidity = 1e18;
        uint256 exchangeRate = pWETH.initialExchangeRate();

        // no withdraw before deposit
        assertEq(
            pUSDC.maxWithdraw(user1), 0, "does not match max withdraw before deposit"
        );
        assertEq(pWETH.convertToShares(liquidity), liquidity * 1e18 / exchangeRate);
        assertEq(pWETH.convertToAssets(liquidity), liquidity * exchangeRate / 1e18);

        ///porivde liquidity
        doDeposit(user1, depositor, address(pWETH), liquidity);

        vm.prank(depositor);
        re.exitMarket(address(pWETH));

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        doBorrow(user1, user1, address(pWETH), 0.7e18);
        uint256 maxWithdraw = pUSDC.maxWithdraw(user1);
        uint256 maxRedeem = pUSDC.maxRedeem(user1);
        assertEq(pUSDC.maxRedeem(user1), pUSDC.convertToShares(maxWithdraw));
        assertEq(maxWithdraw, pUSDC.convertToAssets(maxRedeem));

        vm.prank(user1);
        pUSDC.withdraw(maxWithdraw, user1, user1);
        vm.prank(user1);
        // "RedeemRiskEngineRejection(uint256)" selector
        vm.expectRevert(abi.encodePacked(bytes4(0x9759ead5), uint256(3)));
        pUSDC.withdraw(1, user1, user1);

        vm.prank(depositor);
        // "RedeemTransferOutNotPossible()" selector
        vm.expectRevert(bytes4(0x91240a1b));
        pWETH.withdraw(2e18, depositor, depositor);

        mockOracle.setPrice(address(pWETH), 2500e6, 18);
        // no withdraw with shortfall
        assertEq(
            pUSDC.maxWithdraw(user1), 0, "does not match max withdraw with shortfall"
        );

        changeList(address(pUSDC), false);
        // no withdraw after unlisted
        assertEq(pUSDC.maxWithdraw(user1), 0, "does not match max withdraw after unlist");
    }

    function testBorrow_FailIfNotEnoughCash() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        deal(address(pWETH.asset()), address(pWETH), 0);
        //"BorrowCashNotAvailable()" selector
        doBorrowRevert(
            user1, user1, address(pWETH), 0.745e18, abi.encodePacked(bytes4(0x48c25881))
        );
    }

    function testBorrow_FailIfNotListed() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);
        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);

        changeList(address(pWETH), false);

        //"RepayBorrowRiskEngineRejection(uint256)" selector
        doRepayRevert(
            user1,
            user1,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xbb0619b7), uint256(4))
        );
    }

    function testLiquidate_FailIfNotListed() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);

        changeList(address(pWETH), false);

        //"LiquidateRiskEngineRejection(uint256)" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0xd1192049), uint256(4))
        });

        doLiquidate(lp);
    }

    function testLiquidate_FailIfBorrowerIsLiquidator() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);

        //"LiquidateLiquidatorIsBorrower()" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: user1,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0x6f469884))
        });

        doLiquidate(lp);
    }

    function testLiquidate_FailIfRepayIsZero() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);

        //"LiquidateCloseAmountIsZero()" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 0,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0xd29da7ef))
        });

        doLiquidate(lp);
    }

    function testLiquidate_FailIfPriceIsZero() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);
        mockOracle.setPrice(address(pUSDC), 0, 18);

        //"LiquidateRiskEngineRejection(uint256)" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0xd1192049), uint256(5))
        });

        doLiquidate(lp);
    }

    function testLiquidate_SuccessInEMode() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");
        address[] memory pToken = new address[](2);
        bool[] memory collateralPermissions = new bool[](2);
        bool[] memory borrowPermissions = new bool[](2);

        pToken[0] = address(pWETH);
        pToken[1] = address(pUSDC);

        collateralPermissions[0] = true;
        collateralPermissions[1] = true;
        borrowPermissions[0] = true;
        borrowPermissions[1] = true;

        IRiskEngine.BaseConfiguration memory baseConfig =
            IRiskEngine.BaseConfiguration(82.5e16, 82.5e16, 102e16);

        vm.startPrank(getAdmin());

        re.supportEMode(2, true, pToken, collateralPermissions, borrowPermissions);
        re.configureEMode(2, baseConfig);

        vm.stopPrank();

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        vm.prank(user1);
        re.switchEMode(2);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);

        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: false,
            error: ""
        });

        doLiquidate(lp);
    }

    function testDeposit_FailIfReenter() public {
        address depositor = makeAddr("depositor");

        address pReenter = deployPToken(
            "pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockReentrantToken
        );
        // "ReentrancyGuardReentrantCall()" selector
        doDepositRevert(
            depositor, depositor, pReenter, 2000e6, abi.encodePacked(bytes4(0x3ee5aeb5))
        );
    }
}
