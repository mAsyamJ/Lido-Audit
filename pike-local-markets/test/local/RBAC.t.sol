pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IOwnable} from "@interfaces/IOwnable.sol";
import {RBACModule, IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalRBAC is TestLocal {
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
    }

    function testGrant_FailIfAlreadyGranted() public {
        vm.startPrank(getAdmin());
        // "AlreadyGranted()" selector
        vm.expectRevert(bytes4(0x87b38f77));
        IRBAC(address(re)).grantPermission(configurator_permission, getAdmin());

        vm.expectRevert(bytes4(0x87b38f77));
        IRBAC(address(re)).grantNestedPermission(
            configurator_permission, address(pUSDC), getAdmin()
        );

        vm.stopPrank();
    }

    function testGrant_FailIfInvalidPermission() public {
        vm.startPrank(getAdmin());
        // "InvalidPermission()" selector
        vm.expectRevert(bytes4(0x868a64de));
        IRBAC(address(re)).grantPermission(bytes32(0), getAdmin());

        vm.expectRevert(bytes4(0x868a64de));
        IRBAC(address(re)).grantNestedPermission(bytes32(0), address(pUSDC), getAdmin());

        vm.stopPrank();
    }

    function testGrant_FailIfNotOwner() public {
        vm.startPrank(address(1));
        // "Unauthorized(address)" selector
        vm.expectRevert(abi.encodePacked(bytes4(0x8e4a23d6), abi.encode(address(1))));
        IRBAC(address(re)).grantPermission(bytes32(0), getAdmin());

        vm.expectRevert(abi.encodePacked(bytes4(0x8e4a23d6), abi.encode(address(1))));
        IRBAC(address(re)).grantNestedPermission(bytes32(0), address(pUSDC), getAdmin());

        vm.stopPrank();
    }

    function testAction_FailIfNotPermissioned() public {
        vm.startPrank(address(1));
        // "PermissionDenied(bytes32,address)" selector
        vm.expectRevert(
            abi.encodePacked(
                bytes4(0xc768858b), abi.encode(pause_guard_permission, address(1))
            )
        );
        re.setMintPaused(pWETH, true);

        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(0, 0, 108e16);
        // "PermissionDenied(bytes32,address)" selector
        vm.expectRevert(
            abi.encodePacked(
                bytes4(0xc768858b), abi.encode(configurator_permission, address(1))
            )
        );
        re.configureMarket(pWETH, config);

        vm.stopPrank();
    }

    function testRevoke_Success() public {
        vm.startPrank(getAdmin());
        IRBAC(address(re)).revokePermission(configurator_permission, getAdmin());
        IRBAC(address(re)).revokeNestedPermission(
            configurator_permission, address(pUSDC), getAdmin()
        );

        assertEq(
            IRBAC(address(re)).hasPermission(configurator_permission, getAdmin()),
            false,
            "invalid permission"
        );

        assertEq(
            IRBAC(address(re)).hasNestedPermission(
                configurator_permission, address(pUSDC), getAdmin()
            ),
            false,
            "invalid nested permission"
        );

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        IRBAC(address(re)).hasPermission(configurator_permission, address(0));

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        IRBAC(address(re)).hasNestedPermission(
            configurator_permission, address(pUSDC), address(0)
        );

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        IRBAC(address(re)).hasNestedPermission(
            configurator_permission, address(0), getAdmin()
        );

        vm.stopPrank();
    }

    function testRevoke_FailIfAlreadyRevoked() public {
        vm.startPrank(getAdmin());
        IRBAC(address(re)).revokePermission(configurator_permission, getAdmin());
        IRBAC(address(re)).revokeNestedPermission(
            configurator_permission, address(pUSDC), getAdmin()
        );

        // "AlreadyRevoked()" selector
        vm.expectRevert(bytes4(0x905e7107));
        IRBAC(address(re)).revokePermission(configurator_permission, getAdmin());

        vm.expectRevert(bytes4(0x905e7107));
        IRBAC(address(re)).revokeNestedPermission(
            configurator_permission, address(pUSDC), getAdmin()
        );

        vm.stopPrank();
    }

    function testRenounce_Success() public {
        vm.startPrank(getAdmin());
        IOwnable(address(re)).renounceOwnership();

        assertEq(IOwnable(address(re)).owner(), address(0), "owner not renounced");
        assertEq(
            IOwnable(address(re)).pendingOwner(),
            address(0),
            "pending owner not renounced"
        );

        vm.stopPrank();
    }

    function testNominateOwner_Success() public {
        vm.prank(getAdmin());
        IOwnable(address(re)).nominateNewOwner(address(1));

        assertEq(
            address(1), IOwnable(address(re)).pendingOwner(), "pending owner not set"
        );

        vm.prank(address(1));
        IOwnable(address(re)).acceptOwnership();

        assertEq(address(1), IOwnable(address(re)).owner(), "owner not set");
    }

    function testNominateOwner_Fail() public {
        vm.startPrank(getAdmin());
        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        IOwnable(address(re)).nominateNewOwner(address(0));

        IOwnable(address(re)).nominateNewOwner(address(1));

        // "AlreadyNominated()" selector
        vm.expectRevert(bytes4(0x51e7c1d6));
        IOwnable(address(re)).nominateNewOwner(address(1));

        // "NotPendingOwner()" selector
        vm.expectRevert(bytes4(0x1853971c));
        IOwnable(address(re)).acceptOwnership();

        // "NotNominated()" selector
        vm.expectRevert(bytes4(0x9ceae3db));
        IOwnable(address(re)).renounceNomination();

        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        IOwnable(address(re)).transferOwnership(address(0));
        vm.stopPrank();

        vm.prank(address(1));
        IOwnable(address(re)).renounceNomination();

        assertEq(address(0), IOwnable(address(re)).pendingOwner());

        vm.stopPrank();
    }
}
