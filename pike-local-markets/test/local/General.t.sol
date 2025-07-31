pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalGeneral is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;

    MockOracle mockOracle;

    IRiskEngine re;

    function setUp() public {
        setDebug(true);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockToken);
        deployPToken("pike-weth", "pWETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken);

        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());

        //inital mint
        doInitialMint(pUSDC);
        doInitialMint(pWETH);
    }

    // D: Deposit
    // B: Borrow
    // R: Repay
    // W: Withdraw
    // L: Liquidate
    // T: Transfer

    function testD() public {
        address user1 = makeAddr("user1");
        doDepositAndEnter(user1, user1, address(pUSDC), 100e6);
        (, uint256 liquidity,) = re.getAccountLiquidity(user1);
        (, uint256 borrowLiquidity,) = re.getAccountBorrowLiquidity(user1);
        // max liquidity to allow liquidation for pUSDC is set to 84.5%
        assertEq(liquidity, 84.5e18, "Invalid liquidity");
        // max liquidity to allow borrow for pUSDC is set to 74.5%
        assertEq(borrowLiquidity, 74.5e18, "Invalid liquidity to borrow");
        doMint(user1, user1, address(pWETH), 1e8);
    }

    function testDBehalf() public {
        address user1 = makeAddr("user1");
        address onBehalf = makeAddr("onBehalf");
        doDeposit(user1, onBehalf, address(pUSDC), 100e6);
    }

    function testDB() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        // base rate per second 0
        assertEq(pWETH.borrowRatePerSecond(), baseRate, "Invalid rate per second");

        (, uint256 estimatedLiquidityNeededToBorrow,) =
            re.getHypotheticalAccountLiquidity(user1, address(pWETH), 0, 0.745e18);

        (, uint256 availableLiquidityToBorrow,) = re.getAccountBorrowLiquidity(user1);

        assertEq(
            estimatedLiquidityNeededToBorrow,
            availableLiquidityToBorrow,
            "Mismatch values"
        );

        doBorrow(user1, user1, address(pWETH), 0.745e18);

        assertNotEq(pWETH.borrowRatePerSecond(), 475_646_879, "Invalid rate per second");
    }

    function testDBBehalf() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address onBehalf = makeAddr("onBehalf");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(onBehalf, onBehalf, address(pUSDC), 2000e6);
        // "DelegateNotAllowed()" selector
        doBorrowRevert(
            user1,
            onBehalf,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xf0f402cc))
        );

        doDelegate(onBehalf, user1, pWETH, true);

        doBorrow(user1, onBehalf, address(pWETH), 0.745e18);
    }

    function testDBR() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
        doRepay(user1, user1, address(pWETH), 0.745e18);
    }

    function testDBRBehalf() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address onBehalf = makeAddr("onBehalf");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(onBehalf, onBehalf, address(pUSDC), 2000e6);
        doBorrow(onBehalf, onBehalf, address(pWETH), 0.745e18);
        doRepay(user1, onBehalf, address(pWETH), 0.745e18);
    }

    function testDBRW_Underlying() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
        doRepay(user1, user1, address(pWETH), 0.745e18);
        doWithdrawUnderlying(user1, user1, address(pUSDC), 2000e6);
    }

    function testDBRW() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
        doRepay(user1, user1, address(pWETH), 0.745e18);
        doWithdraw(user1, user1, address(pUSDC), 2000e6);
    }

    function testDBRWBehalf_Underlying() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address onBehalf = makeAddr("onBehalf");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(onBehalf, onBehalf, address(pUSDC), 2000e6);
        doBorrow(onBehalf, onBehalf, address(pWETH), 0.745e18);
        doRepay(onBehalf, onBehalf, address(pWETH), 0.745e18);
        uint256 withdrawBalance = pUSDC.balanceOfUnderlying(onBehalf);
        uint256 expectedToken = pUSDC.previewWithdraw(withdrawBalance);
        // "InsufficientAllowance(address,uint256,uint256)" selector
        doWithdrawUnderlyingRevert(
            user1,
            onBehalf,
            address(pUSDC),
            withdrawBalance,
            abi.encodePacked(
                bytes4(0x192b9e4e),
                abi.encode(address(user1), uint256(0), uint256(expectedToken))
            )
        );

        doAllow(onBehalf, user1, pUSDC, expectedToken);
        doWithdrawUnderlying(user1, onBehalf, address(pUSDC), withdrawBalance);
    }

    function testDBRWBehalf() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address onBehalf = makeAddr("onBehalf");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(onBehalf, onBehalf, address(pUSDC), 2000e6);
        doBorrow(onBehalf, onBehalf, address(pWETH), 0.745e18);
        doRepay(onBehalf, onBehalf, address(pWETH), 0.745e18);
        uint256 withdrawBalance = pUSDC.balanceOf(onBehalf);
        // "InsufficientAllowance(address,uint256,uint256)" selector
        doWithdrawRevert(
            user1,
            onBehalf,
            address(pUSDC),
            withdrawBalance,
            abi.encodePacked(
                bytes4(0x192b9e4e),
                abi.encode(address(user1), uint256(0), uint256(withdrawBalance))
            )
        );

        doAllow(onBehalf, user1, pUSDC, withdrawBalance);

        doWithdraw(user1, onBehalf, address(pUSDC), withdrawBalance);
    }

    function testDBL() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

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

    function testDT() public {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        doDeposit(sender, sender, address(pUSDC), 100e6);

        doTransfer(sender, sender, receiver, address(pUSDC), 50e6);
        // "TransferNotAllowed()" selector
        doTransferRevert(
            sender,
            sender,
            sender,
            address(pUSDC),
            50e6,
            abi.encodePacked(bytes4(0x8cd22d19))
        );
        uint256 withdrawBalance = pUSDC.balanceOf(sender);
        // "InsufficientAllowance(address,uint256,uint256)" selector
        doTransferRevert(
            receiver,
            sender,
            receiver,
            address(pUSDC),
            withdrawBalance,
            abi.encodePacked(
                bytes4(0x192b9e4e),
                abi.encode(address(receiver), uint256(0), uint256(withdrawBalance))
            )
        );

        // approve
        vm.prank(sender);
        pUSDC.approve(receiver, withdrawBalance);
        assertEq(pUSDC.allowance(sender, receiver), withdrawBalance);

        doTransfer(receiver, sender, receiver, address(pUSDC), withdrawBalance);
    }

    function testDBT() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);

        // TransferRiskEngineRejection(3) selector
        doTransferRevert(
            user1,
            user1,
            depositor,
            address(pUSDC),
            50e6,
            abi.encodePacked(bytes4(0x90420254), uint256(3))
        );
    }
}
