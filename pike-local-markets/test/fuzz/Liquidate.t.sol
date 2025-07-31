pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestFuzz} from "@helpers/TestFuzz.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract FuzzLiquidate is TestFuzz {
    IPToken pUSDC;
    IPToken pWETH;
    IRiskEngine re;

    MockOracle mockOracle;

    address borrower;
    address onBehalfOf;
    address liquidator;
    uint256 usdcPrice;
    uint256 wethPrice;
    uint256 wethCF;
    uint256 wethLF;
    uint256 wethToDeposit;
    uint256 usdcToBorrow;
    uint256 usdcToRepay;
    uint256 pTokenTotalSupply;
    uint256 totalBorrows;
    uint256 cash;
    uint256 usdcTotalSupply;
    uint256 usdcTotalBorrows;
    uint256 usdcCash;
    uint256 wethTotalSupply;
    uint256 wethTotalBorrows;
    uint256 wethCash;

    function setUp() public {
        setDebug(false);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockToken);
        deployPToken("pike-weth", "pWETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken);

        wethCF = 72.5e16;

        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");

        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());

        //inital mint
        doInitialMint(pUSDC);
        doInitialMint(pWETH);
    }

    function testFuzz_liquidate(address[3] memory addresses, uint256[9] memory amounts)
        public
    {
        borrower = addresses[0];
        onBehalfOf = addresses[1];
        liquidator = addresses[2];
        pTokenTotalSupply = amounts[6];
        totalBorrows = amounts[7];
        cash = amounts[8];

        /// bound usdc price 0.98-1.02$
        usdcPrice = bound(amounts[0], 0.98e6, 1.02e6);
        /// bound weth price 1000-4000$
        wethPrice = bound(amounts[1], 1000e6, 4000e6);
        /// bound liquidation factor 40-90%
        wethLF = bound(amounts[2], wethCF, 90e16);
        /// bound usdc 1000-400M$
        wethToDeposit = bound(amounts[3], 1e18, 1e23);
        /// needs to borrow with small deviation from CF(± 0.00001%)
        usdcToBorrow = bound(
            amounts[4],
            1e6,
            wethToDeposit * wethPrice * (wethCF - 0.00001e16) / (usdcPrice * 1e30)
        );
        usdcToRepay = bound(amounts[5], 1, usdcToBorrow / 2);
        usdcCash = bound(cash, 10e6, 1e15);
        usdcCash = Math.max(usdcCash, usdcToBorrow);
        usdcTotalBorrows = bound(totalBorrows, 10e6, 1e15);
        usdcTotalSupply = bound(pTokenTotalSupply, 10e6, (usdcCash + usdcTotalBorrows));
        wethCash = bound(cash, 1e10, 400e21);
        wethTotalBorrows = bound(totalBorrows, 1e10, 400e21);
        wethTotalSupply = bound(pTokenTotalSupply, 1e10, (wethCash + wethTotalBorrows));

        vm.assume(
            borrower != address(pUSDC) && borrower != address(pWETH)
                && borrower != address(0)
        );
        vm.assume(
            onBehalfOf != address(pUSDC) && onBehalfOf != address(pWETH)
                && onBehalfOf != address(0)
        );
        vm.assume(
            liquidator != address(pUSDC) && liquidator != address(pWETH)
                && liquidator != address(0) && liquidator != onBehalfOf
        );

        /// set boundry for exchangeRate ratio (with 20% apr per year it takes 40 years to 8x)
        vm.assume((usdcCash + usdcTotalBorrows) / usdcTotalSupply < 8);
        vm.assume((wethCash + wethTotalBorrows) / wethTotalSupply < 8);

        vm.prank(getAdmin());
        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(wethCF, wethLF, 108e16);
        re.configureMarket(pWETH, config);
        mockOracle.setPrice(address(pWETH), wethPrice, 18);
        mockOracle.setPrice(address(pUSDC), usdcPrice, 6);

        setPTokenTotalSupply(address(pUSDC), usdcTotalSupply);
        setTotalBorrows(address(pUSDC), usdcTotalBorrows);
        deal(address(pUSDC.asset()), address(pUSDC), usdcCash);

        setPTokenTotalSupply(address(pWETH), wethTotalSupply);
        setTotalBorrows(address(pWETH), wethTotalBorrows);
        deal(address(pWETH.asset()), address(pWETH), wethCash);
        if (borrower != onBehalfOf) {
            vm.prank(onBehalfOf);
            re.updateDelegate(borrower, true);
        }

        doDepositAndEnter(borrower, onBehalfOf, address(pWETH), wethToDeposit);
        doBorrow(borrower, onBehalfOf, address(pUSDC), usdcToBorrow);

        /// usdcToBorrow * usdcPrice / (wethLF * wethToDeposit) = price in which collateral is liquidatable
        mockOracle.setPrice(
            address(pWETH),
            (usdcToBorrow * usdcPrice * 1e30 / (wethLF * wethToDeposit)),
            18
        );

        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: onBehalfOf,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: usdcToRepay,
            expectRevert: false,
            error: ""
        });

        doLiquidate(lp);
    }
}
