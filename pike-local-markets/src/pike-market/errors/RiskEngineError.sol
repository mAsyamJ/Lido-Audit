//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Library for riskEngine errors.
 */
library RiskEngineError {
    enum Error {
        NO_ERROR,
        RISKENGINE_MISMATCH,
        INSUFFICIENT_SHORTFALL,
        INSUFFICIENT_LIQUIDITY,
        MARKET_NOT_LISTED,
        PRICE_ERROR,
        TOO_MUCH_REPAY,
        SUPPLY_CAP_EXCEEDED,
        BORROW_CAP_EXCEEDED,
        NOT_ALLOWED_AS_COLLATERAL,
        NOT_ALLOWED_TO_BORROW,
        EMODE_NOT_ALLOWED
    }

    error ExitMarketRedeemRejection(uint256 errorCode);
    error SwitchEMode(uint256 errorCode);
    error InvalidCollateralStatus(address pToken);
    error InvalidBorrowStatus(address pToken);

    error MintPaused();
    error BorrowPaused();
    error SeizePaused();
    error TransferPaused();

    error SenderNotPToken();
    error RepayMoreThanBorrowed();

    error MarketNotListed();
    error InvalidCollateralFactor();
    error InvalidPrice();
    error InvalidLiquidationThreshold();
    error InvalidIncentiveThreshold();
    error InvalidReserveShare();
    error InvalidCloseFactor();

    error AlreadyListed();
    error NotListed();

    error InvalidCategory();

    error PTokenNotAllowedToBorrow();

    error AlreadyInEMode();

    error DelegationStatusUnchanged();
}
