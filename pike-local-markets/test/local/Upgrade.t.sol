pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IOwnable} from "@interfaces/IOwnable.sol";
import {RBACModule, IRBAC} from "@modules/common/RBACModule.sol";
import {UpgradeModule, IUpgrade} from "@modules/common/UpgradeModule.sol";
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

        // impl slot to write on diamond
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        vm.store(address(re), slot, bytes32(abi.encode(address(re), bool(false))));
        vm.store(address(pUSDC), slot, bytes32(abi.encode(address(pUSDC), bool(false))));
    }

    function testUpgrade_Success() public {
        address mockImpl = IUpgrade(address(pUSDC)).getImplementation();

        vm.prank(getAdmin());
        IUpgrade(address(re)).upgradeTo(mockImpl);

        assertEq(IUpgrade(address(re)).getImplementation(), mockImpl, "failed to upgrade");
    }

    function testUpgrade_Fail() public {
        address mockContract = address(new RBACModule());

        vm.startPrank(getAdmin());
        // "ZeroAddress()" selector
        vm.expectRevert(bytes4(0xd92e233d));
        IUpgrade(address(re)).upgradeTo(address(0));

        // "NotAContract(address)" selector
        vm.expectRevert(abi.encodePacked(bytes4(0x8a8b41ec), abi.encode(address(1))));
        IUpgrade(address(re)).upgradeTo(address(1));

        // "ImplementationIsSterile(address)" selector
        vm.expectRevert(abi.encodePacked(bytes4(0x15504301), abi.encode(mockContract)));
        IUpgrade(address(re)).upgradeTo(mockContract);
    }
}
