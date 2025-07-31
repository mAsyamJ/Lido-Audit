// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestDeploy} from "@helpers/TestDeploy.sol";

contract TestUtilities is TestDeploy {
    uint256 constant ONE_MANTISSA = 1e18;
    uint256 constant SECONDS_PER_YEAR = 31_536_000;

    function getActionStateData(
        address user,
        address onBehalfOf,
        address pTokenAddress,
        address tokenAddress
    ) public view returns (ActionStateData memory data) {
        IPToken pToken = IPToken(pTokenAddress);

        uint256 userUnderlyingBalance = IERC20(tokenAddress).balanceOf(user);

        uint256 collateral = pToken.balanceOfUnderlying(onBehalfOf);

        uint256 borrowed = pToken.borrowBalanceCurrent(onBehalfOf);
        UserData memory userData = UserData(userUnderlyingBalance, collateral, borrowed);
        PTokenData memory pTokenData = PTokenData({
            totalCash: pToken.getCash(),
            totalBorrow: pToken.totalBorrowsCurrent(),
            totalReserve: pToken.totalReservesCurrent(),
            totalSupply: pToken.totalSupply(),
            totalSupplyUnderlying: pToken.totalAssets()
        });

        data = ActionStateData(pTokenData, userData);

        if (getDebug()) {
            console.log(
                "Balance of pToken %s is (deposited: %s, borrowed: %s)",
                pToken.name(),
                userData.collateral,
                userData.borrowed
            );
        }
    }

    function getLiquidationStateData(LiquidationStateParams memory data)
        public
        view
        returns (LiquidationStateData memory lsd)
    {
        IPToken collateralPToken = IPToken(data.collateralPToken);
        IPToken borrowedPToken = IPToken(data.borrowedPToken);

        PTokenData memory collateralPTokenData = PTokenData({
            totalCash: collateralPToken.getCash(),
            totalBorrow: collateralPToken.totalBorrowsCurrent(),
            totalReserve: collateralPToken.totalReservesCurrent(),
            totalSupply: collateralPToken.totalSupply(),
            totalSupplyUnderlying: collateralPToken.totalAssets()
        });

        PTokenData memory borrowedPTokenData = PTokenData({
            totalCash: borrowedPToken.getCash(),
            totalBorrow: borrowedPToken.totalBorrowsCurrent(),
            totalReserve: borrowedPToken.totalReservesCurrent(),
            totalSupply: borrowedPToken.totalSupply(),
            totalSupplyUnderlying: borrowedPToken.totalAssets()
        });

        uint256 prankAddressUnderlyingBalance =
            IERC20(data.underlyingRepayToken).balanceOf(data.prankAddress);

        uint256 userToLiquidateUnderlyingBalance =
            IERC20(data.underlyingRepayToken).balanceOf(data.userToLiquidate);

        uint256 prankAddressCollateral = collateralPToken.balanceOf(data.prankAddress);

        uint256 userToLiquidateCollateral =
            collateralPToken.balanceOf(data.userToLiquidate);

        UserData memory prankAddressData = UserData({
            underlyingBalance: prankAddressUnderlyingBalance,
            collateral: prankAddressCollateral,
            borrowed: borrowedPToken.borrowBalanceCurrent(data.prankAddress)
        });

        UserData memory userToLiquidateData = UserData({
            underlyingBalance: userToLiquidateUnderlyingBalance,
            collateral: userToLiquidateCollateral,
            borrowed: borrowedPToken.borrowBalanceCurrent(data.userToLiquidate)
        });

        lsd = LiquidationStateData(
            prankAddressData,
            userToLiquidateData,
            collateralPTokenData,
            borrowedPTokenData
        );

        (,, uint256 shortfall) =
            collateralPToken.riskEngine().getAccountLiquidity(data.userToLiquidate);

        if (getDebug()) {
            console.log(
                "Balance of borrowed %s is %s",
                borrowedPToken.name(),
                lsd.userToLiquidateData.borrowed
            );
            console.log(
                "Balance of collateral %s is %s",
                collateralPToken.name(),
                lsd.userToLiquidateData.collateral
            );
            console.log(
                "Account is %s (shortfall: %s)",
                shortfall == 0 ? "healthy" : "underwater",
                shortfall
            );
        }
    }

    function requireActionDataValid(
        Action action,
        address pTokenAddress,
        uint256 preview,
        uint256 amount,
        ActionStateData memory beforeData,
        ActionStateData memory afterData,
        bool expectRevert
    ) public view {
        uint256 exchangeRateStored = IPToken(pTokenAddress).exchangeRateStored();

        if (action == Action.MINT) {
            uint256 mintAmount = amount * exchangeRateStored / ONE_MANTISSA;
            if (!expectRevert) {
                require(
                    preview
                        == afterData.userData.collateral - beforeData.userData.collateral,
                    "Does not match preview mint"
                );
                require(
                    beforeData.pTokenData.totalSupplyUnderlying + mintAmount
                        == afterData.pTokenData.totalSupplyUnderlying,
                    "Did not transfer token to total supply ptoken"
                );
                require(
                    beforeData.pTokenData.totalCash + mintAmount
                        == afterData.pTokenData.totalCash,
                    "Did not transfer token to pToken"
                );
                assertApproxEqRel(
                    beforeData.userData.collateral + mintAmount,
                    afterData.userData.collateral,
                    1e12, // ± 0.0001000000000000%
                    "Did not deposit in pToken"
                );
                require(
                    beforeData.pTokenData.totalSupply + amount
                        == afterData.pTokenData.totalSupply,
                    "Did not increase total supply"
                );
                require(
                    beforeData.userData.underlyingBalance
                        == mintAmount + afterData.userData.underlyingBalance,
                    "Did not transfer token from user"
                );
            } else {
                require(
                    beforeData.pTokenData.totalSupplyUnderlying
                        == afterData.pTokenData.totalSupplyUnderlying,
                    "Did transfer token to total supply ptoken"
                );
                require(
                    beforeData.pTokenData.totalCash == afterData.pTokenData.totalCash,
                    "Did transfer token to pToken"
                );
                require(
                    beforeData.userData.collateral == afterData.userData.collateral,
                    "Did deposit in pToken"
                );
                require(
                    beforeData.pTokenData.totalSupply == afterData.pTokenData.totalSupply,
                    "Did increase total supply"
                );
                require(
                    beforeData.userData.underlyingBalance
                        == afterData.userData.underlyingBalance,
                    "Did transfer token from user"
                );
            }
        } else if (action == Action.SUPPLY) {
            uint256 mintTokens = amount * ONE_MANTISSA / exchangeRateStored;
            if (!expectRevert) {
                require(
                    preview
                        == afterData.pTokenData.totalSupply
                            - beforeData.pTokenData.totalSupply,
                    "Does not match preview deposit"
                );
                require(
                    beforeData.pTokenData.totalSupplyUnderlying + amount
                        == afterData.pTokenData.totalSupplyUnderlying,
                    "Did not transfer token to total supply ptoken"
                );
                require(
                    beforeData.pTokenData.totalCash + amount
                        == afterData.pTokenData.totalCash,
                    "Did not transfer token to pToken"
                );
                assertApproxEqRel(
                    beforeData.userData.collateral + amount,
                    afterData.userData.collateral,
                    1e12, // ± 0.0001000000000000%
                    "Did not deposit in pToken"
                );
                require(
                    beforeData.pTokenData.totalSupply + mintTokens
                        == afterData.pTokenData.totalSupply,
                    "Did not increase total supply"
                );
                require(
                    beforeData.userData.underlyingBalance
                        == amount + afterData.userData.underlyingBalance,
                    "Did not transfer token from user"
                );
            } else {
                require(
                    beforeData.pTokenData.totalSupplyUnderlying
                        == afterData.pTokenData.totalSupplyUnderlying,
                    "Did not transfer token to total supply ptoken"
                );
                require(
                    beforeData.pTokenData.totalCash == afterData.pTokenData.totalCash,
                    "Did transfer token to pToken"
                );
                require(
                    beforeData.userData.collateral == afterData.userData.collateral,
                    "Did deposit in pToken"
                );
                require(
                    beforeData.pTokenData.totalSupply == afterData.pTokenData.totalSupply,
                    "Did increase total supply"
                );
                require(
                    beforeData.userData.underlyingBalance
                        == afterData.userData.underlyingBalance,
                    "Did transfer token from user"
                );
            }
        } else if (action == Action.REPAY) {
            if (amount >= beforeData.userData.borrowed) {
                amount = beforeData.userData.borrowed;
            }
            require(
                beforeData.pTokenData.totalSupplyUnderlying
                    == afterData.pTokenData.totalSupplyUnderlying,
                "Did not transfer token to total supply ptoken"
            );
            if (!expectRevert) {
                require(
                    amount + afterData.pTokenData.totalBorrow
                        == beforeData.pTokenData.totalBorrow,
                    "Did not repay to ptoken"
                );
                require(
                    amount + afterData.userData.borrowed == beforeData.userData.borrowed,
                    "Did not repay for user"
                );
                require(
                    beforeData.pTokenData.totalCash + amount
                        == afterData.pTokenData.totalCash,
                    "Did not transfer token to ptoken"
                );
                require(
                    beforeData.userData.underlyingBalance
                        == amount + afterData.userData.underlyingBalance,
                    "Did not transfer token from user"
                );
            } else {
                require(
                    afterData.pTokenData.totalBorrow == beforeData.pTokenData.totalBorrow,
                    "Did repay to ptoken"
                );
                require(
                    afterData.userData.borrowed == beforeData.userData.borrowed,
                    "Did repay for user"
                );
                require(
                    beforeData.pTokenData.totalCash == afterData.pTokenData.totalCash,
                    "Did transfer token to ptoken"
                );
                require(
                    beforeData.userData.underlyingBalance
                        == afterData.userData.underlyingBalance,
                    "Did transfer token from user"
                );
            }
        } else if (action == Action.WITHDRAW || action == Action.WITHDRAW_UNDERLYING) {
            uint256 redeemTokens;
            if (action == Action.WITHDRAW) {
                redeemTokens = amount;
                amount = amount * exchangeRateStored / ONE_MANTISSA;
            } else {
                redeemTokens = amount * ONE_MANTISSA / exchangeRateStored;
            }
            if (!expectRevert) {
                if (action == Action.WITHDRAW) {
                    require(
                        preview
                            == beforeData.pTokenData.totalSupplyUnderlying
                                - afterData.pTokenData.totalSupplyUnderlying,
                        "Does not match preview redeem"
                    );
                } else if (action == Action.WITHDRAW_UNDERLYING) {
                    require(
                        preview
                            == beforeData.pTokenData.totalSupply
                                - afterData.pTokenData.totalSupply,
                        "Does not match preview withdraw"
                    );
                }
                assertApproxEqRel(
                    beforeData.pTokenData.totalSupplyUnderlying,
                    afterData.pTokenData.totalSupplyUnderlying + amount,
                    1e11, // ± 0.0000100000000000%
                    "Did not transfer token to total supply ptoken"
                );
                assertApproxEqRel(
                    beforeData.pTokenData.totalSupply,
                    redeemTokens + afterData.pTokenData.totalSupply,
                    1e11, // ± 0.0000100000000000%
                    "Did not withdraw from ptoken"
                );
                assertApproxEqRel(
                    beforeData.userData.collateral,
                    amount + afterData.userData.collateral,
                    1e12, // ± 0.0001000000000000%
                    "Did not withdraw from user"
                );
                assertApproxEqRel(
                    beforeData.pTokenData.totalCash,
                    amount + afterData.pTokenData.totalCash,
                    1e12, // ± 0.0001000000000000%
                    "Did not transfer money from pToken"
                );
                assertApproxEqRel(
                    beforeData.userData.underlyingBalance + amount,
                    afterData.userData.underlyingBalance,
                    1e12, // ± 0.0001000000000000%
                    "Did not transfer money to user"
                );
            } else {
                require(
                    beforeData.pTokenData.totalSupplyUnderlying
                        == afterData.pTokenData.totalSupplyUnderlying,
                    "Did not transfer token to total supply ptoken"
                );
                require(
                    beforeData.pTokenData.totalSupply == afterData.pTokenData.totalSupply,
                    "Did withdraw from ptoken"
                );
                require(
                    beforeData.userData.collateral == afterData.userData.collateral,
                    "Did withdraw from user"
                );
                require(
                    beforeData.pTokenData.totalCash == afterData.pTokenData.totalCash,
                    "Did transfer money from pToken"
                );
                require(
                    beforeData.userData.underlyingBalance
                        == afterData.userData.underlyingBalance,
                    "Did transfer money to user"
                );
            }
        } else if (action == Action.BORROW) {
            require(
                beforeData.pTokenData.totalSupplyUnderlying
                    == afterData.pTokenData.totalSupplyUnderlying,
                "Did not transfer token to total supply ptoken"
            );
            if (!expectRevert) {
                require(
                    afterData.pTokenData.totalBorrow
                        == beforeData.pTokenData.totalBorrow + amount,
                    "Did not borrow from ptoken"
                );
                require(
                    afterData.userData.borrowed == beforeData.userData.borrowed + amount,
                    "Did not borrow for user"
                );
                require(
                    beforeData.pTokenData.totalCash
                        == amount + afterData.pTokenData.totalCash,
                    "Did not transfer token from ptoken"
                );
                require(
                    beforeData.userData.underlyingBalance + amount
                        == afterData.userData.underlyingBalance,
                    "Did not transfer token to user"
                );
            } else {
                require(
                    afterData.pTokenData.totalBorrow == beforeData.pTokenData.totalBorrow,
                    "Did borrow from ptoken"
                );
                require(
                    afterData.userData.borrowed == beforeData.userData.borrowed,
                    "Did borrow for user"
                );
                require(
                    beforeData.pTokenData.totalCash == afterData.pTokenData.totalCash,
                    "Did transfer token from ptoken"
                );
                require(
                    beforeData.userData.underlyingBalance
                        == afterData.userData.underlyingBalance,
                    "Did transfer token to user"
                );
            }
        }
    }

    function requireLiquidationDataValid(
        LiquidationParams memory lp,
        LiquidationStateData memory beforeData,
        LiquidationStateData memory afterData
    ) public view {
        IRiskEngine riskEngine = IPToken(lp.collateralPToken).riskEngine();

        // we assume repay amount is equal to what is transferred
        (, uint256 seizeTokens) = riskEngine.liquidateCalculateSeizeTokens(
            lp.userToLiquidate, lp.borrowedPToken, lp.collateralPToken, lp.repayAmount
        );

        uint256 protocolSeizeToken = seizeTokens
            * IPToken(lp.collateralPToken).protocolSeizeShareMantissa() / ONE_MANTISSA;

        uint256 protocolSeizeAmount = protocolSeizeToken
            * IPToken(lp.collateralPToken).exchangeRateCurrent() / ONE_MANTISSA;

        uint256 liquidatorSeizeShare = seizeTokens - protocolSeizeToken;
        if (!lp.expectRevert) {
            require(
                beforeData.prankAddressData.underlyingBalance
                    == afterData.prankAddressData.underlyingBalance + lp.repayAmount,
                "Money did not transfer from liquidator"
            );
            require(
                beforeData.borrowedPTokenData.totalCash + lp.repayAmount
                    == afterData.borrowedPTokenData.totalCash,
                "Did not deposit to ptoken"
            );
            assertApproxEqRel(
                beforeData.prankAddressData.collateral + liquidatorSeizeShare,
                afterData.prankAddressData.collateral,
                1e3, // ± 0.0000000000001000%
                "Collateral did not transfer to liquidator"
            );
            assertApproxEqRel(
                beforeData.userToLiquidateData.collateral,
                afterData.userToLiquidateData.collateral + seizeTokens,
                1e3, // ± 0.0000000000001000%
                "Collateral did not transfer from borrower"
            );
            require(
                beforeData.collateralPTokenData.totalSupply
                    == afterData.collateralPTokenData.totalSupply + protocolSeizeToken,
                "Collateral ptoken did not transfer to protocol"
            );
            assertApproxEqRel(
                beforeData.collateralPTokenData.totalReserve + protocolSeizeAmount,
                afterData.collateralPTokenData.totalReserve,
                1e3, // ± 0.0000000000001000%
                "Collateral underlying ptoken did not transfer to protocol reserve"
            );
            require(
                beforeData.userToLiquidateData.borrowed
                    == afterData.userToLiquidateData.borrowed + lp.repayAmount,
                "Borrow did not subtract from borrower"
            );
            require(
                beforeData.borrowedPTokenData.totalBorrow
                    == afterData.borrowedPTokenData.totalBorrow + lp.repayAmount,
                "Borrow did not subtract from total borrow of ptoken"
            );
        } else {
            require(
                beforeData.prankAddressData.underlyingBalance
                    == afterData.prankAddressData.underlyingBalance,
                "Money did transfer from liquidator"
            );
            require(
                beforeData.borrowedPTokenData.totalCash
                    == afterData.borrowedPTokenData.totalCash,
                "Did deposit to ptoken"
            );
            require(
                beforeData.prankAddressData.collateral
                    == afterData.prankAddressData.collateral,
                "Collateral did transfer to liquidator"
            );
            require(
                beforeData.userToLiquidateData.collateral
                    == afterData.userToLiquidateData.collateral,
                "Collateral did transfer from borrower"
            );
            require(
                beforeData.collateralPTokenData.totalSupply
                    == afterData.collateralPTokenData.totalSupply,
                "Collateral ptoken did transfer to protocol"
            );
            require(
                beforeData.collateralPTokenData.totalReserve
                    == afterData.collateralPTokenData.totalReserve,
                "Collateral underlying ptoken did transfer to protocol reserve"
            );
            require(
                beforeData.userToLiquidateData.borrowed
                    == afterData.userToLiquidateData.borrowed,
                "Borrow did subtract from borrower"
            );
            require(
                beforeData.borrowedPTokenData.totalBorrow
                    == afterData.borrowedPTokenData.totalBorrow,
                "Borrow did subtract from total borrow of ptoken"
            );
        }
    }
}
