pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";
import {IRBAC} from "@modules/common/RBACModule.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalEMode is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;
    IPToken pSTETH;

    MockOracle mockOracle;

    IRiskEngine re;

    uint8 categoryId = 1;

    address[] pToken = new address[](2);
    bool[] collateralPermissions = new bool[](2);
    bool[] borrowPermissions = new bool[](2);

    function setUp() public {
        setDebug(false);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockToken);
        deployPToken("pike-weth", "pWETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken);
        deployPToken(
            "pike-steth", "pSTETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken
        );

        /// eth price = 2000$, usdc price = 1$
        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
        pSTETH = getPToken("pSTETH");
        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());

        pToken[0] = address(pWETH);
        pToken[1] = address(pSTETH);

        collateralPermissions[0] = false;
        collateralPermissions[1] = true;
        borrowPermissions[0] = true;
        borrowPermissions[1] = false;

        IRiskEngine.BaseConfiguration memory baseConfig =
            IRiskEngine.BaseConfiguration(90e16, 93e16, 102e16);

        vm.startPrank(getAdmin());

        re.supportEMode(
            categoryId, true, pToken, collateralPermissions, borrowPermissions
        );
        re.configureEMode(categoryId, baseConfig);
        (address[] memory colTokens, address[] memory borTokens) =
            re.emodeMarkets(categoryId);
        // steth as collateral
        assertEq(colTokens[0], pToken[1]);
        // weth as borrowable
        assertEq(borTokens[0], pToken[0]);

        vm.stopPrank();

        assertEq(re.liquidationIncentive(categoryId, pToken[0]), 102e16);
        assertEq(re.liquidationIncentive(categoryId, pToken[1]), 102e16);

        address depositor = makeAddr("depositor");
        doDeposit(depositor, depositor, address(pWETH), 10e18);
        doDeposit(depositor, depositor, address(pSTETH), 10e18);
    }

    function testSupportEMode_Fail() public {
        bool[] memory newArray = new bool[](1);
        vm.startPrank(getAdmin());

        // "InvalidCategory()" selector
        vm.expectRevert(bytes4(0xd67592f6));
        re.supportEMode(0, true, pToken, collateralPermissions, borrowPermissions);

        // "NoArrayParity()" selector
        vm.expectRevert(bytes4(0x266c51bb));
        re.supportEMode(2, true, pToken, newArray, borrowPermissions);

        pToken[1] = address(1);

        // "NotListed()" selector
        vm.expectRevert(bytes4(0x665c1c57));
        re.supportEMode(2, true, pToken, collateralPermissions, borrowPermissions);

        IRiskEngine.BaseConfiguration memory baseConfig =
            IRiskEngine.BaseConfiguration(90e16, 93e17, 102e16);

        // "InvalidCategory()" selector
        vm.expectRevert(bytes4(0xd67592f6));
        re.configureEMode(0, baseConfig);

        // "InvalidLiquidationThreshold()" selector
        vm.expectRevert(bytes4(0x3e51d2c0));
        re.configureEMode(1, baseConfig);

        baseConfig = IRiskEngine.BaseConfiguration(94e16, 93e16, 102e16);
        // "InvalidLiquidationThreshold()" selector
        vm.expectRevert(bytes4(0x3e51d2c0));
        re.configureEMode(1, baseConfig);

        baseConfig = IRiskEngine.BaseConfiguration(90e16, 93e16, 10e16);
        // "InvalidIncentiveThreshold()" selector
        vm.expectRevert(bytes4(0x37fbf6a6));
        re.configureEMode(1, baseConfig);

        vm.stopPrank();
    }

    function testSwitchEMode_Success() public {
        address user1 = makeAddr("user1");
        // deposit and unsupported asset and switch to emode
        doDeposit(user1, user1, address(pUSDC), 2000e6);

        vm.prank(user1);
        re.exitMarket(address(pUSDC));

        vm.prank(user1);
        re.switchEMode(1);

        assertEq(re.accountCategory(user1), 1);

        // should not enter if asset not supported only supply
        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        assertEq(re.checkCollateralMembership(user1, pUSDC), false);

        doDepositAndEnter(user1, user1, address(pSTETH), 1e18);
        // with e-mode should be able to borrow up to 90% CF
        doBorrow(user1, user1, address(pWETH), 90e16);
        // decrease debt to 70e16 to met default mode 70% CF
        doRepay(user1, user1, address(pWETH), 20e16);

        // switch to default mode with 72.5% CF
        vm.prank(user1);
        re.switchEMode(0);
    }

    function testSwitchEMode_FailIfNotSupported() public {
        address user1 = makeAddr("user1");
        // deposit an unsupported asset and enable as collateral
        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        // fail for unsupported USDC in e-mode as collateral
        // "InvalidCollateralStatus(address)" selector
        vm.startPrank(user1);
        vm.expectRevert(abi.encodePacked(bytes4(0x0f3b8268), abi.encode(address(pUSDC))));
        re.switchEMode(1);

        // should able to switch after disable collateral
        re.exitMarket(address(pUSDC));
        re.switchEMode(1);
        vm.stopPrank();

        address[] memory ptokens = new address[](1);
        ptokens[0] = address(pWETH);
        // should fail to enable collateral for unsupported asset in e-mode (weth)
        doDeposit(user1, user1, address(pWETH), 1e18);
        vm.prank(user1);
        re.enterMarkets(ptokens);
        assertEq(re.checkCollateralMembership(user1, pWETH), false);
        // "BorrowRiskEngineRejection(uint256)" selector
        doDepositAndEnter(user1, user1, address(pSTETH), 1e18);
        // should fail to borrow unsupported asset in e-mode
        doBorrowRevert(
            user1,
            user1,
            address(pSTETH),
            5e17,
            abi.encodePacked(bytes4(0xcd617e38), abi.encode(10))
        );

        // switch to default
        vm.prank(user1);
        re.switchEMode(0);

        doBorrow(user1, user1, address(pSTETH), 5e17);
        // fail for unsupported USDC in e-mode as borrow
        // "InvalidBorrowStatus(address)" selector
        vm.prank(user1);
        vm.expectRevert(abi.encodePacked(bytes4(0xde3a9c2d), abi.encode(address(pSTETH))));
        re.switchEMode(1);
    }

    function testSwitchEMode_FailIfNotAllowed() public {
        address user1 = makeAddr("user1");

        vm.prank(user1);
        re.switchEMode(1);

        doDepositAndEnter(user1, user1, address(pSTETH), 1e18);
        doBorrow(user1, user1, address(pWETH), 5e17);
        doBorrow(user1, user1, address(pWETH), 4e17);

        assertEq(re.checkBorrowMembership(user1, pWETH), true);

        vm.startPrank(user1);
        // fail if e-mode is make shortfall
        // "SwitchEMode(uint256)" selector
        vm.expectRevert(abi.encodePacked(bytes4(0x19085eda), abi.encode(3)));
        re.switchEMode(0);

        // fail if e-mode is not supported
        // "InvalidCategory()" selector
        vm.expectRevert(abi.encodePacked(bytes4(0xd67592f6)));
        re.switchEMode(2);

        // fail if e-mode is already activated
        // "AlreadyInEMode()" selector
        vm.expectRevert(abi.encodePacked(bytes4(0x99f962a0)));
        re.switchEMode(1);

        vm.stopPrank();

        vm.prank(getAdmin());
        re.supportEMode(1, false, pToken, collateralPermissions, borrowPermissions);

        // "MintRiskEngineRejection(uint256)" selector
        doDepositRevert(
            user1,
            user1,
            address(pSTETH),
            1,
            abi.encodePacked(bytes4(0x1d3413fb), uint256(11))
        );

        // "RedeemRiskEngineRejection(uint256)" selector
        doWithdrawRevert(
            user1,
            user1,
            address(pSTETH),
            1,
            abi.encodePacked(bytes4(0x9759ead5), uint256(11))
        );
    }
}
