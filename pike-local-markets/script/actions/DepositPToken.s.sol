// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPToken} from "@interfaces/IPToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Config} from "../Config.sol";
import {console} from "forge-std/console.sol";

contract DepositPToken is Config {
    function run() public payable {
        string memory chain = vm.envString("CHAIN");
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");
        string memory pTokenName = vm.envString("PTOKEN_NAME");
        uint256 depositAmount = vm.envUint("DEPOSIT_AMOUNT");

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        string memory baseDir = getBaseDir(chain, false); // Always false to use main folder
        string memory deploymentPath = string(
            abi.encodePacked(
                baseDir, "/protocol-", vm.toString(protocolId), "/deploymentData.json"
            )
        );
        string memory deploymentJson = vm.readFile(deploymentPath);

        // Construct the key (e.g., "market-pusdc" from "pUSDC")
        string memory pTokenKey = string(abi.encodePacked("market-", pTokenName));
        address pTokenAddress =
            vm.parseJsonAddress(deploymentJson, string(abi.encodePacked(".", pTokenKey)));
        require(pTokenAddress != address(0), "PToken not found in deployment data");

        IPToken pToken = IPToken(pTokenAddress);
        IERC20 underlying = IERC20(pToken.asset());
        address depositor = vm.addr(deployerPrivateKey);

        console.log("Depositing into PToken: %s", pTokenName);
        console.log("PToken Address: %s", pTokenAddress);
        console.log("Underlying Asset: %s", address(underlying));
        console.log("Depositor: %s", depositor);
        console.log("Deposit Amount: %s", depositAmount);

        vm.startBroadcast(deployerPrivateKey);
        // Approve the PToken to spend the underlying asset
        underlying.approve(pTokenAddress, depositAmount);
        // Deposit into the PToken
        pToken.deposit(depositAmount, depositor);
        vm.stopBroadcast();

        // Log the PToken balance after deposit
        uint256 pTokenBalance = pToken.balanceOf(depositor);
        console.log("PToken Balance after deposit: %s", pTokenBalance);
    }
}
