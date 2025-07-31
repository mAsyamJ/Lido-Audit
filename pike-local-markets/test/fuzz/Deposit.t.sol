pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestFuzz} from "@helpers/TestFuzz.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract FuzzDeposit is TestFuzz {
    IPToken pUSDC;
    IPToken pWETH;
    IRiskEngine re;

    MockOracle mockOracle;

    address depositor;
    address onBehalfOf;
    uint256 underlyingToDeposit;
    uint256 pTokenTotalSupply;
    uint256 totalBorrows;
    uint256 cash;

    function setUp() public {
        setDebug(false);
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

    function testFuzz_deposit(address[2] memory addresses, uint256[4] memory amounts)
        public
    {
        depositor = addresses[0];
        onBehalfOf = addresses[1];

        /// bound usdc 10-1B$
        underlyingToDeposit = bound(amounts[0], 10e6, 1e15);
        /// set cash, totalBorrows and totalSupply to get random exchangeRate
        cash = bound(amounts[1], 10e6, 1e15);
        totalBorrows = bound(amounts[2], 10e6, 1e15);
        pTokenTotalSupply = bound(amounts[3], 10e6, (totalBorrows + cash));

        vm.assume(depositor != address(pUSDC) && depositor != address(0));
        vm.assume(onBehalfOf != address(pUSDC) && onBehalfOf != address(0));
        /// set boundry for exchangeRate ratio (with 20% apr per year it takes 40 years to 8x)
        vm.assume((cash + totalBorrows) / pTokenTotalSupply < 8);

        setPTokenTotalSupply(address(pUSDC), pTokenTotalSupply);
        setTotalBorrows(address(pUSDC), totalBorrows);
        deal(address(pUSDC.asset()), address(pUSDC), cash);

        doDepositAndEnter(depositor, onBehalfOf, address(pUSDC), underlyingToDeposit);

        (, uint256 liquidity,) = re.getAccountLiquidity(onBehalfOf);
        (, uint256 borrowLiquidity,) = re.getAccountBorrowLiquidity(onBehalfOf);
        // max liquidity to allow liquidation for pUSDC is set to 84.5%
        assertApproxEqRel(
            liquidity,
            84.5e10 * underlyingToDeposit,
            1e12, // ± 0.0001000000000000%
            "Invalid liquidity"
        );
        // max liquidity to allow borrow for pUSDC is set to 74.5%
        assertApproxEqRel(
            borrowLiquidity,
            74.5e10 * underlyingToDeposit,
            1e12, // ± 0.0001000000000000%
            "Invalid liquidity to borrow"
        );
    }

    function testFuzz_depositWithBorrowLimit(
        address[2] memory addresses,
        uint256[4] memory amounts
    ) public {
        depositor = addresses[0];
        onBehalfOf = addresses[1];

        /// bound usdc 10-1B$
        underlyingToDeposit = bound(amounts[0], 10e6, 1e15);
        /// set cash, totalBorrows and totalSupply to get random exchangeRate
        cash = bound(amounts[1], 10e6, 1e15);
        totalBorrows = bound(amounts[2], 10e6, 1e15);
        pTokenTotalSupply = bound(amounts[3], 10e6, (totalBorrows + cash));

        vm.assume(depositor != address(pUSDC) && depositor != address(0));
        vm.assume(onBehalfOf != address(pUSDC) && onBehalfOf != address(0));
        /// set boundry for exchangeRate ratio (with 20% apr per year it takes 40 years to 8x)
        vm.assume((cash + totalBorrows) / pTokenTotalSupply < 8);

        setPTokenTotalSupply(address(pUSDC), pTokenTotalSupply);
        setTotalBorrows(address(pUSDC), totalBorrows);

        setBorrowCapToZero();

        deal(address(pUSDC.asset()), address(pUSDC), cash);
        doDepositAndEnter(depositor, onBehalfOf, address(pUSDC), underlyingToDeposit);

        (, uint256 liquidity,) = re.getAccountLiquidity(onBehalfOf);
        (, uint256 borrowLiquidity,) = re.getAccountBorrowLiquidity(onBehalfOf);
        // max liquidity to allow liquidation for pUSDC is set to 84.5%
        assertApproxEqRel(
            liquidity,
            84.5e10 * underlyingToDeposit,
            1e12, // ± 0.0001000000000000%
            "Invalid liquidity"
        );
        // max liquidity to allow borrow for pUSDC is set to 74.5%
        assertApproxEqRel(
            borrowLiquidity,
            74.5e10 * underlyingToDeposit,
            1e12, // ± 0.0001000000000000%
            "Invalid liquidity to borrow"
        );
    }

    function setBorrowCapToZero() internal {
        IPToken[] memory markets = new IPToken[](1);
        markets[0] = IPToken(pUSDC);

        uint256[] memory caps = new uint256[](1);
        caps[0] = 0;
        vm.prank(getAdmin());
        re.setMarketBorrowCaps(markets, caps);
    }
}
