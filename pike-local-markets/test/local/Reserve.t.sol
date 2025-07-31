pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalReserve is TestLocal {
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
    }

    function testAddReserve_Success() public {
        address user1 = makeAddr("user1");
        uint256 value = 1e18;

        deal(pWETH.asset(), user1, value);

        uint256 reserveBefore = pWETH.totalReserves();

        vm.startPrank(user1);
        IERC20(pWETH.asset()).approve(address(pWETH), value);
        pWETH.addReserves(value);

        uint256 reserveAfter = pWETH.totalReserves();

        assertEq(reserveBefore + value, reserveAfter);
    }

    function testReduceReserve_Success() public {
        address user1 = makeAddr("user1");
        uint256 value = 1e18;

        deal(pWETH.asset(), user1, value);

        vm.startPrank(user1);
        IERC20(pWETH.asset()).approve(address(pWETH), value);
        pWETH.addReserves(value);

        vm.startPrank(getAdmin());
        uint256 reserveBefore = pWETH.totalReserves();

        pWETH.reduceReservesEmergency(value);
        pWETH.reduceReservesOwner(0);
        pWETH.reduceReservesConfigurator(0);

        uint256 reserveAfter = pWETH.totalReserves();

        assertEq(reserveBefore, reserveAfter + value);
    }

    function testSweepERC20_Success() public {
        address user1 = makeAddr("user1");
        uint256 value = 1e18;

        deal(pWETH.asset(), user1, value);

        vm.startPrank(user1);
        IERC20(pWETH.asset()).transfer(address(pUSDC), value);

        vm.startPrank(getAdmin());

        uint256 balanceBefore = IERC20(pWETH.asset()).balanceOf(address(pUSDC));
        uint256 adminBalanceBefore = IERC20(pWETH.asset()).balanceOf(getAdmin());

        pUSDC.sweepToken(IERC20(pWETH.asset()));

        uint256 balanceAfter = IERC20(pWETH.asset()).balanceOf(address(pUSDC));
        uint256 adminBalanceAfter = IERC20(pWETH.asset()).balanceOf(getAdmin());

        assertEq(balanceBefore, balanceAfter + value);
        assertEq(adminBalanceAfter, adminBalanceBefore + value);
    }

    function testSetProtocolSeizeShare() public {
        // 2%
        uint256 newSeizeShare = 2e16;

        assertNotEq(pWETH.protocolSeizeShareMantissa(), newSeizeShare);

        vm.prank(getAdmin());
        pWETH.setProtocolSeizeShare(newSeizeShare);

        assertEq(pWETH.protocolSeizeShareMantissa(), newSeizeShare);
    }

    function testSetReserveShares_Fail() public {
        // "InvalidReserveShare()" selector
        vm.prank(getAdmin());
        vm.expectRevert(bytes4(0x8415fb41));
        re.setReserveShares(ONE_MANTISSA, ONE_MANTISSA);
    }

    function testSetReserveFactor() public {
        // 10%
        uint256 newReserveFactor = 5e16;

        assertNotEq(pWETH.reserveFactorMantissa(), newReserveFactor);

        vm.prank(getAdmin());
        pWETH.setReserveFactor(newReserveFactor);

        assertEq(pWETH.reserveFactorMantissa(), newReserveFactor);
    }

    function testReserveFactor_FailIfOutOfBound() public {
        vm.prank(getAdmin());
        // "SetReserveFactorBoundsCheck()" selector
        vm.expectRevert(bytes4(0xe2e441e6));
        pUSDC.setReserveFactor(10e18);
    }

    function testReduceReserve_FailIfMoreThanBalance() public {
        deal(address(pUSDC.asset()), address(pUSDC), 1e18);

        vm.prank(getAdmin());
        // "ReduceReservesCashNotAvailable()" selector
        vm.expectRevert(bytes4(0x3345e999));
        pUSDC.reduceReservesEmergency(1e18 + 1);
    }

    function testReduceReserve_FailIfNotValid() public {
        deal(address(pUSDC.asset()), address(pUSDC), 1e18);

        vm.prank(getAdmin());
        // "ReduceReservesCashValidation()" selector
        vm.expectRevert(bytes4(0xf1a5300a));
        pUSDC.reduceReservesEmergency(1e18);
    }

    function testReduceReserve_FailIfNotPermitted() public {
        deal(address(pUSDC.asset()), address(pUSDC), 1e18);

        vm.startPrank(address(1));
        // "PermissionDenied(bytes32,address)" selector
        vm.expectRevert(
            abi.encodePacked(
                bytes4(0xc768858b), abi.encode(emergency_withdrawer, address(1))
            )
        );
        pUSDC.reduceReservesEmergency(1e18);

        // "PermissionDenied(bytes32,address)" selector
        vm.expectRevert(
            abi.encodePacked(
                bytes4(0xc768858b), abi.encode(reserve_withdrawer_permission, address(1))
            )
        );
        pUSDC.reduceReservesConfigurator(1e18);

        // "PermissionDenied(bytes32,address)" selector
        vm.expectRevert(
            abi.encodePacked(bytes4(0xc768858b), abi.encode(owner_withdrawer, address(1)))
        );
        pUSDC.reduceReservesOwner(1e18);
    }
}
