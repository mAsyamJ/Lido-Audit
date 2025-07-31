pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestFuzz} from "@helpers/TestFuzz.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract FuzzDoubleJumpRate is TestFuzz {
    IPToken pUSDC;
    IInterestRateModel irm;

    uint256 cash;
    uint256 borrows;
    uint256 reserves;

    function setUp() public {
        setDebug(false);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockToken);

        pUSDC = getPToken("pUSDC");
        irm = getIRM("pUSDC");
    }

    function testFuzz_rateBoundary(uint256[3] memory amounts) public {
        /// bound usdc borrow 0-1B
        borrows = bound(amounts[0], 0, 1e15);

        /// bound usdc reserve 0-100M
        reserves = bound(amounts[1], 0, 100e12);
        // vm.assume(cash + borrows > reserves);
        cash = bound(amounts[2], reserves, reserves * 200);

        uint256 utilizationRate = irm.getUtilization(cash, borrows, reserves);
        uint256 borrowRate;

        if (utilizationRate <= kink1) {
            // ur=0-5% br=0%
            borrowRate = irm.getBorrowRate(cash, borrows, reserves);
            assertEq(borrowRate, 0, "Invalid low slope");
        }
        if (utilizationRate <= kink2) {
            // ur=5-95% br=0-5.5%
            borrowRate = irm.getBorrowRate(cash, borrows, reserves) * SECONDS_PER_YEAR;
            assert(borrowRate <= 5.5e16);
        }
        if (utilizationRate > kink2) {
            // ur=95% br>5.5%
            borrowRate = irm.getBorrowRate(cash, borrows, reserves) * SECONDS_PER_YEAR;
            assert(borrowRate > 5.5e16);
        }
    }
}
