//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Library for pToken errors.
 */
library PTokenError {
    error SetReserveFactorFreshCheck();

    error SetReserveFactorBoundsCheck();
    error SetProtocolSeizeShareBoundsCheck();

    error MintRiskEngineRejection(uint256 errorCode);
    error MintFreshnessCheck();
    error ZeroTokensMinted();

    error RedeemRiskEngineRejection(uint256 errorCode);
    error RedeemFreshnessCheck();
    error RedeemTransferOutNotPossible();
    error InvalidRedeemTokens();
    error OnlyOneInputAllowed();

    error BorrowRiskEngineRejection(uint256 errorCode);
    error BorrowFreshnessCheck();
    error BorrowCashNotAvailable();

    error RepayBorrowRiskEngineRejection(uint256 errorCode);
    error RepayBorrowFreshnessCheck();

    error LiquidateAccrueCollateralInterestFailed();

    error LiquidateRiskEngineRejection(uint256 errorCode);
    error LiquidateFreshnessCheck();
    error LiquidateCollateralFreshnessCheck();
    error LiquidateLiquidatorIsBorrower();
    error LiquidateCloseAmountIsZero();
    error LiquidateCloseAmountIsUintMax();
    error LiquidateCalculateAmountSeizeFailed(uint256 errorCode);
    error LiquidateSeizeTooMuch();

    error LiquidateSeizeRiskEngineRejection(uint256 errorCode);

    error AddReservesFactorFreshCheck();
    error ReduceReservesFreshCheck();
    error ReduceReservesCashNotAvailable();
    error ReduceReservesCashValidation();

    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error TransferNotAllowed();
    error TransferRiskEngineRejection(uint256 errorCode);
    error SweepNotAllowed();

    error DelegateNotAllowed();
}
