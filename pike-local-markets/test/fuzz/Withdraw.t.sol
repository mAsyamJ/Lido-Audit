pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestFuzz} from "@helpers/TestFuzz.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract FuzzWithdraw is TestFuzz {
    IPToken pUSDC;
    IPToken pWETH;
    IRiskEngine re;

    MockOracle mockOracle;

    address withdrawer;
    address onBehalfOf;
    uint256 underlyingToDeposit;
    uint256 underlyingToWithdraw;
    uint256 pTokenToWithdraw;
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

    function testFuzz_withdrawUnderlying(
        address[2] memory addresses,
        uint256[5] memory amounts
    ) public {
        withdrawer = addresses[0];
        onBehalfOf = addresses[1];

        /// bound usdc 10-1B$
        underlyingToDeposit = bound(amounts[0], 20e6, 1e15);
        /// set cash, totalBorrows and totalSupply to get random exchangeRate
        cash = bound(amounts[4], 10e6, 1e15);
        totalBorrows = bound(amounts[3], 10e6, 1e15);
        pTokenTotalSupply = bound(amounts[2], 10e6, (totalBorrows + cash));

        vm.assume(withdrawer != address(pUSDC) && withdrawer != address(0));
        vm.assume(onBehalfOf != address(pUSDC) && onBehalfOf != address(0));
        /// set boundry for exchangeRate ratio (with 20% apr per year it takes 40 years to 8x)
        vm.assume((cash + totalBorrows) / pTokenTotalSupply < 8);

        setPTokenTotalSupply(address(pUSDC), pTokenTotalSupply);
        setTotalBorrows(address(pUSDC), totalBorrows);
        deal(address(pUSDC.asset()), address(pUSDC), cash);
        if (withdrawer != onBehalfOf) {
            vm.prank(onBehalfOf);
            pUSDC.approve(withdrawer, type(uint256).max);
        }

        doDepositAndEnter(withdrawer, onBehalfOf, address(pUSDC), underlyingToDeposit);

        underlyingToWithdraw =
            bound(amounts[1], 10e6, pUSDC.balanceOfUnderlying(onBehalfOf));

        doWithdrawUnderlying(withdrawer, onBehalfOf, address(pUSDC), underlyingToWithdraw);
    }

    function testFuzz_withdraw(address[2] memory addresses, uint256[5] memory amounts)
        public
    {
        withdrawer = addresses[0];
        onBehalfOf = addresses[1];

        /// bound usdc 10-1B$
        underlyingToDeposit = bound(amounts[0], 10e6, 1e15);
        /// set cash, totalBorrows and totalSupply to get random exchangeRate
        cash = bound(amounts[4], 10e6, 1e15);
        totalBorrows = bound(amounts[3], 10e6, 1e15);
        pTokenTotalSupply = bound(amounts[2], 10e6, (totalBorrows + cash));

        vm.assume(withdrawer != address(pUSDC) && withdrawer != address(0));
        vm.assume(onBehalfOf != address(pUSDC) && onBehalfOf != address(0));
        /// set boundry for exchangeRate ratio (with 20% apr per year it takes 40 years to 8x)
        vm.assume((cash + totalBorrows) / pTokenTotalSupply < 8);

        setPTokenTotalSupply(address(pUSDC), pTokenTotalSupply);
        setTotalBorrows(address(pUSDC), totalBorrows);
        deal(address(pUSDC.asset()), address(pUSDC), cash);
        if (withdrawer != onBehalfOf) {
            vm.prank(onBehalfOf);
            pUSDC.approve(withdrawer, type(uint256).max);
        }

        doDepositAndEnter(withdrawer, onBehalfOf, address(pUSDC), underlyingToDeposit);

        pTokenToWithdraw = bound(amounts[1], 1, pUSDC.balanceOf(onBehalfOf));
        doWithdraw(withdrawer, onBehalfOf, address(pUSDC), pTokenToWithdraw);
    }
}
