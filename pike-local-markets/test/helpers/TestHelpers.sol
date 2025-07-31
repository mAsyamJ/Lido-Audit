// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {TestUtilities} from "@helpers/TestUtilities.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

contract TestHelpers is TestUtilities {
    function doAction(ActionParameters memory params) public {
        address user = params.prankAddress;
        bool onBehalfOf = params.onBehalfOf != params.prankAddress;

        vm.deal(user, 1 ether);

        Action action = Action(params.action);

        if (getDebug()) {
            console.log("-[User %s]--------------", params.onBehalfOf);
        }

        if (action == Action.MINT || action == Action.SUPPLY || action == Action.REPAY) {
            if (action == Action.MINT) {
                deal(params.tokenAddress, user, type(uint256).max);
                vm.prank(user);
                IERC20(params.tokenAddress).approve(params.pToken, type(uint256).max);
            } else {
                deal(params.tokenAddress, user, params.amount);
                vm.prank(user);
                IERC20(params.tokenAddress).approve(params.pToken, params.amount);
            }
        }

        ActionStateData memory beforeAction = getActionStateData(
            user, params.onBehalfOf, params.pToken, params.tokenAddress
        );

        uint256 preview;

        vm.recordLogs();
        if (action == Action.MINT) {
            if (getDebug()) {
                console.log(
                    "Minting %s of %s", params.amount, IPToken(params.tokenAddress).name()
                );
            }
            preview = IPToken(params.pToken).previewMint(params.amount);
            vm.prank(user);
            if (params.expectRevert) {
                vm.expectRevert(params.error);
            }
            IPToken(params.pToken).mint(params.amount, params.onBehalfOf);
        } else if (action == Action.SUPPLY) {
            if (getDebug()) {
                console.log(
                    "Depositing %s of %s",
                    params.amount,
                    IPToken(params.tokenAddress).name()
                );
            }

            preview = IPToken(params.pToken).previewDeposit(params.amount);
            vm.prank(user);
            if (params.expectRevert) {
                vm.expectRevert(params.error);
            }
            IPToken(params.pToken).deposit(params.amount, params.onBehalfOf);
        } else if (action == Action.REPAY) {
            if (getDebug()) {
                console.log(
                    "Repaying %s of %s",
                    params.amount,
                    IPToken(params.tokenAddress).name()
                );
            }

            if (onBehalfOf) {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).repayBorrowOnBehalfOf(
                    params.onBehalfOf, params.amount
                );
            } else {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).repayBorrow(params.amount);
            }
        } else if (action == Action.BORROW) {
            if (getDebug()) {
                console.log(
                    "Borrowing %s of %s",
                    params.amount,
                    IPToken(params.tokenAddress).name()
                );
            }

            if (onBehalfOf) {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).borrowOnBehalfOf(params.onBehalfOf, params.amount);
            } else {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).borrow(params.amount);
            }
        } else if (action == Action.WITHDRAW_UNDERLYING) {
            if (getDebug()) {
                console.log(
                    "Withdrawing %s of %s",
                    params.amount,
                    IPToken(params.tokenAddress).name()
                );
            }

            preview = IPToken(params.pToken).previewWithdraw(params.amount);
            vm.prank(user);
            if (params.expectRevert) {
                vm.expectRevert(params.error);
            }
            IPToken(params.pToken).withdraw(params.amount, user, params.onBehalfOf);
        } else if (action == Action.WITHDRAW) {
            if (getDebug()) {
                console.log(
                    "Withdrawing %s of %s", params.amount, IPToken(params.pToken).name()
                );
            }

            preview = IPToken(params.pToken).previewRedeem(params.amount);
            vm.prank(user);
            if (params.expectRevert) {
                vm.expectRevert(params.error);
            }
            IPToken(params.pToken).redeem(params.amount, user, params.onBehalfOf);
        }

        ActionStateData memory afterAction = getActionStateData(
            user, params.onBehalfOf, params.pToken, params.tokenAddress
        );

        requireActionDataValid(
            action,
            params.pToken,
            preview,
            params.amount,
            beforeAction,
            afterAction,
            params.expectRevert
        );

        if (getDebug()) {
            console.log("----------------------------------------");
            console.log("");
        }
    }

    function doInitialMint(IPToken pToken) public {
        address user = address(0xdead);
        address asset = IPToken(pToken).asset();

        vm.deal(user, 1 ether);

        deal(asset, user, 1e18);
        vm.startPrank(user);
        IERC20(asset).approve(address(pToken), 1e18);
        pToken.mint(5000, user);
        vm.stopPrank();
    }

    function doInitialMintRevert(IPToken pToken) public {
        address user = address(0xdead);
        address asset = IPToken(pToken).asset();

        vm.deal(user, 1 ether);

        deal(asset, user, 1e18);
        vm.startPrank(user);
        IERC20(asset).approve(address(pToken), 1e18);

        // "ZeroTokensMinted()" selector
        vm.expectRevert(bytes4(0x4ba25a38));
        pToken.mint(1000, user);
        vm.stopPrank();
    }

    function _doTransfer(TransferParameters memory params) public {
        address user = params.prankAddress;
        bool onBehalfOf = params.onBehalfOf != params.prankAddress;

        vm.deal(user, 1 ether);

        if (getDebug()) {
            console.log("-[User %s]--------------", params.onBehalfOf);
        }

        uint256 senderBalanceBefore = IPToken(params.pToken).balanceOf(params.onBehalfOf);
        uint256 receiverBalanceBefore = IPToken(params.pToken).balanceOf(params.receiver);

        vm.recordLogs();
        if (getDebug()) {
            console.log(
                "Transferring %s of %s to %s",
                params.amount,
                IPToken(params.pToken).name(),
                params.receiver
            );
        }

        if (onBehalfOf) {
            vm.prank(user);
            if (params.expectRevert) {
                vm.expectRevert(params.error);
            }
            IPToken(params.pToken).transferFrom(
                params.onBehalfOf, params.receiver, params.amount
            );
        } else {
            vm.prank(user);
            if (params.expectRevert) {
                vm.expectRevert(params.error);
            }
            IPToken(params.pToken).transfer(params.receiver, params.amount);
        }

        uint256 senderBalanceAfter = IPToken(params.pToken).balanceOf(params.onBehalfOf);
        uint256 receiverBalanceAfter = IPToken(params.pToken).balanceOf(params.receiver);

        if (!params.expectRevert) {
            require(
                senderBalanceAfter + params.amount == senderBalanceBefore,
                "Did not transfer ptoken from sender"
            );
            require(
                receiverBalanceBefore + params.amount == receiverBalanceAfter,
                "Did not transfer ptoken to receiver"
            );
        } else {
            require(
                senderBalanceAfter == senderBalanceBefore,
                "Did transfer ptoken from sender"
            );
            require(
                receiverBalanceBefore == receiverBalanceAfter,
                "Did transfer ptoken to receiver"
            );
        }

        if (getDebug()) {
            console.log("----------------------------------------");
            console.log("");
        }
    }

    function doDeposit(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.SUPPLY,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: false,
                error: "",
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doMint(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.MINT,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: false,
                error: "",
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doDepositAndEnter(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.SUPPLY,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: false,
                error: "",
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
        enterMarket(onBehalfOf, pToken);
    }

    function doDepositRevert(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount,
        bytes memory err
    ) public {
        doAction(
            ActionParameters({
                action: Action.SUPPLY,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: true,
                error: err,
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doBorrow(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.BORROW,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: false,
                error: "",
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doBorrowRevert(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount,
        bytes memory err
    ) public {
        doAction(
            ActionParameters({
                action: Action.BORROW,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: true,
                error: err,
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doRepay(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.REPAY,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: false,
                error: "",
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doRepayRevert(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount,
        bytes memory err
    ) public {
        doAction(
            ActionParameters({
                action: Action.REPAY,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: true,
                error: err,
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doWithdraw(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.WITHDRAW,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: false,
                error: "",
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doWithdrawRevert(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount,
        bytes memory err
    ) public {
        doAction(
            ActionParameters({
                action: Action.WITHDRAW,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: true,
                error: err,
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doWithdrawUnderlying(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.WITHDRAW_UNDERLYING,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: false,
                error: "",
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doWithdrawUnderlyingRevert(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount,
        bytes memory err
    ) public {
        doAction(
            ActionParameters({
                action: Action.WITHDRAW_UNDERLYING,
                pToken: pToken,
                tokenAddress: IPToken(pToken).asset(),
                amount: amount,
                expectRevert: true,
                error: err,
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doDelegate(
        address prankAddress,
        address delegate,
        IPToken pToken,
        bool approved
    ) public {
        IRiskEngine re = pToken.riskEngine();
        vm.prank(prankAddress);
        re.updateDelegate(delegate, approved);
    }

    function doAllow(
        address prankAddress,
        address delegate,
        IPToken pToken,
        uint256 value
    ) public {
        vm.prank(prankAddress);
        pToken.approve(delegate, value);
    }

    function doTransfer(
        address prankAddress,
        address onBehalfOf,
        address receiver,
        address pToken,
        uint256 amount
    ) public {
        _doTransfer(
            TransferParameters({
                pToken: pToken,
                receiver: receiver,
                amount: amount,
                expectRevert: false,
                error: "",
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doTransferRevert(
        address prankAddress,
        address onBehalfOf,
        address receiver,
        address pToken,
        uint256 amount,
        bytes memory err
    ) public {
        _doTransfer(
            TransferParameters({
                pToken: pToken,
                receiver: receiver,
                amount: amount,
                expectRevert: true,
                error: err,
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function enterMarket(address prankAddress, address pToken) public {
        address re = address(IPToken(pToken).riskEngine());
        address[] memory markets = new address[](1);
        markets[0] = pToken;
        vm.prank(prankAddress);
        IRiskEngine(re).enterMarkets(markets);
    }

    function doLiquidate(LiquidationParams memory lp) public {
        if (getDebug()) {
            console.log("-[Liquidator %s]--------------", lp.prankAddress);
        }

        address underlyingRepayToken = IPToken(lp.borrowedPToken).asset();

        deal(underlyingRepayToken, lp.prankAddress, lp.repayAmount);
        vm.prank(lp.prankAddress);
        IERC20(underlyingRepayToken).approve(lp.borrowedPToken, lp.repayAmount);

        LiquidationStateParams memory data = LiquidationStateParams({
            prankAddress: lp.prankAddress,
            userToLiquidate: lp.userToLiquidate,
            collateralPToken: lp.collateralPToken,
            borrowedPToken: lp.borrowedPToken,
            underlyingRepayToken: underlyingRepayToken
        });

        LiquidationStateData memory beforeData = getLiquidationStateData(data);

        if (getDebug()) {
            console.log(
                "Liquidating with repaying %s of %s",
                lp.repayAmount,
                IPToken(underlyingRepayToken).name()
            );
        }
        vm.prank(lp.prankAddress);
        if (lp.expectRevert) {
            vm.expectRevert(lp.error);
        }
        IPToken(lp.borrowedPToken).liquidateBorrow(
            lp.userToLiquidate, lp.repayAmount, IPToken(lp.collateralPToken)
        );

        LiquidationStateData memory afterData = getLiquidationStateData(data);

        requireLiquidationDataValid(lp, beforeData, afterData);

        if (getDebug()) {
            console.log("----------------------------------------");
            console.log("");
        }
    }

    function changeList(address pToken, bool approved) public {
        // markets mapping slot with pToken as key
        bytes32 slot = keccak256(
            abi.encode(
                pToken, 0x045c767dd6aa575c77a2f8d1bda11e214b14b47092bcc4f410a939f824586805
            )
        );
        vm.store(
            address(getRiskEngine()), slot, approved ? bytes32(uint256(1)) : bytes32(0)
        );
    }

    function setTotalReserves(address pToken, uint256 totalReserves) public {
        // totalReserves slot
        bytes32 slot = 0x0be5863c0c782626615eed72fc4c521bcfabebe439cbc2683e49afadb49a0d0b;
        vm.store(pToken, slot, bytes32(totalReserves));
    }

    function setRiskEngineSlot(address pToken, address newRiskEngine) public {
        vm.store(
            pToken,
            0x0be5863c0c782626615eed72fc4c521bcfabebe439cbc2683e49afadb49a0d03,
            bytes32(uint256(uint160(newRiskEngine)) << 8)
        );
    }

    function setTotalBorrows(address pToken, uint256 totalBorrows) public {
        // totalBorrows slot
        bytes32 slot = 0x0be5863c0c782626615eed72fc4c521bcfabebe439cbc2683e49afadb49a0d0a;
        vm.store(pToken, slot, bytes32(totalBorrows));
    }

    function setPTokenTotalSupply(address pToken, uint256 totalSupply) public {
        // totalSupply slot
        bytes32 slot = 0x0be5863c0c782626615eed72fc4c521bcfabebe439cbc2683e49afadb49a0d0c;
        vm.store(pToken, slot, bytes32(totalSupply));
    }
}
