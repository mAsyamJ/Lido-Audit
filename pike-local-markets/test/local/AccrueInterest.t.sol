pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalAccrueInterest is TestLocal {
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

    function testDBwithInterestInNormalSlope() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doDepositAndEnter(user2, user2, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
        doBorrow(user2, user2, address(pWETH), 0.2e18);

        uint256 collateralBefore = pWETH.balanceOfUnderlying(depositor);
        uint256 borrowBefore1 = pWETH.borrowBalanceCurrent(user1);
        uint256 borrowBefore2 = pWETH.borrowBalanceCurrent(user2);

        // get rates per second at time of supply and borrow
        uint256 supplyRate = pWETH.supplyRatePerSecond();
        uint256 borrowRate = pWETH.borrowRatePerSecond();

        uint256 borrowInterest1 = borrowBefore1 * borrowRate * 365 days / ONE_MANTISSA;
        uint256 borrowInterest2 = borrowBefore2 * borrowRate * 365 days / ONE_MANTISSA;
        uint256 supplyInterest = collateralBefore * supplyRate * 365 days / ONE_MANTISSA;

        // skip 1 year
        skip(365 days);

        uint256 collateralAfter = pWETH.balanceOfUnderlying(depositor);
        uint256 borrowAfter1 = pWETH.borrowBalanceCurrent(user1);
        uint256 borrowAfter2 = pWETH.borrowBalanceCurrent(user2);

        assertEq(
            borrowBefore1 + borrowInterest1,
            borrowAfter1,
            "borrow interest 1 is inaccurate"
        );
        assertEq(
            borrowBefore2 + borrowInterest2,
            borrowAfter2,
            "borrow interest 2 is inaccurate"
        );

        assertApproxEqRel(
            collateralBefore + supplyInterest,
            collateralAfter,
            1e8, // ± 0.0000000100000000%
            "supply interest is inaccurate"
        );
    }

    function testDBwithInterestInHighSlope() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doDepositAndEnter(user2, user2, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
        doBorrow(user2, user2, address(pWETH), 0.21e18);

        uint256 collateralBefore = pWETH.balanceOfUnderlying(depositor);
        uint256 borrowBefore1 = pWETH.borrowBalanceCurrent(user1);
        uint256 borrowBefore2 = pWETH.borrowBalanceCurrent(user2);

        // get rates per second at time of supply and borrow
        uint256 supplyRate = pWETH.supplyRatePerSecond();
        uint256 borrowRate = pWETH.borrowRatePerSecond();

        uint256 borrowInterest1 = borrowBefore1 * borrowRate * 365 days / ONE_MANTISSA;
        uint256 borrowInterest2 = borrowBefore2 * borrowRate * 365 days / ONE_MANTISSA;
        uint256 supplyInterest = collateralBefore * supplyRate * 365 days / ONE_MANTISSA;

        // skip 1 year
        skip(365 days);

        uint256 collateralAfter = pWETH.balanceOfUnderlying(depositor);
        uint256 borrowAfter1 = pWETH.borrowBalanceCurrent(user1);
        uint256 borrowAfter2 = pWETH.borrowBalanceCurrent(user2);

        assertEq(
            borrowBefore1 + borrowInterest1,
            borrowAfter1,
            "borrow interest 1 is inaccurate"
        );
        assertEq(
            borrowBefore2 + borrowInterest2,
            borrowAfter2,
            "borrow interest 2 is inaccurate"
        );

        assertApproxEqRel(
            collateralBefore + supplyInterest,
            collateralAfter,
            1e8, // ± 0.0000000100000000%
            "supply interest is inaccurate"
        );
    }

    function testRealTimeVariables() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);

        // skip 1 year
        skip(365 days);

        uint256 exchangeRateCurrent = pWETH.exchangeRateCurrent();
        uint256 borrowCurrent = pWETH.borrowBalanceCurrent(user1);
        uint256 totalBorrowCurrent = pWETH.totalBorrowsCurrent();
        uint256 totalReserveCurrent = pWETH.totalReservesCurrent();
        uint256 ownerReservesCurrent = pWETH.ownerReservesCurrent();
        uint256 configuratorReservesCurrent = pWETH.configuratorReservesCurrent();

        uint256 currentSupplyRate = IInterestRateModel(address(pWETH)).getSupplyRate(
            pWETH.getCash(),
            pWETH.totalBorrowsCurrent(),
            pWETH.totalReservesCurrent(),
            pWETH.reserveFactorMantissa()
        );
        uint256 currentBorrowRate = IInterestRateModel(address(pWETH)).getBorrowRate(
            pWETH.getCash(), pWETH.totalBorrowsCurrent(), pWETH.totalReservesCurrent()
        );

        pWETH.accrueInterest();

        uint256 exchangeRateStored = pWETH.exchangeRateStored();
        uint256 borrowStored = pWETH.borrowBalanceStored(user1);
        uint256 totalBorrowStored = pWETH.totalBorrows();
        uint256 totalReserveStored = pWETH.totalReserves();
        uint256 ownerReservesStored = pWETH.ownerReserves();
        uint256 configuratorReservesStored = pWETH.configuratorReserves();

        assertEq(exchangeRateStored, exchangeRateCurrent, "unexpected exchange rate");
        assertEq(borrowStored, borrowCurrent, "unexpected borrow amount");
        assertEq(totalBorrowStored, totalBorrowCurrent, "unexpected total borrow amount");
        assertEq(
            totalReserveStored, totalReserveCurrent, "unexpected total reserve amount"
        );
        assertEq(
            ownerReservesCurrent, ownerReservesStored, "unexpected total reserve amount"
        );
        assertEq(
            configuratorReservesCurrent,
            configuratorReservesStored,
            "unexpected total reserve amount"
        );
        assertEq(currentBorrowRate, pWETH.borrowRatePerSecond(), "unexpected borrow rate");
        assertEq(currentSupplyRate, pWETH.supplyRatePerSecond(), "unexpected supply rate");
    }
}
