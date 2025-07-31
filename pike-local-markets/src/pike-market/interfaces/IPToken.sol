// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    IERC4626, IERC20
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

interface IPToken is IERC4626 {
    /**
     * @notice Event emitted when risk engine is changed
     */
    event NewRiskEngine(IRiskEngine oldRiskEngine, IRiskEngine newRiskEngine);

    /**
     * @notice Event emitted when underlying is borrowed
     */
    event Borrow(
        address borrower,
        address onBehalfOf,
        uint256 borrowAmount,
        uint256 accountBorrows,
        uint256 totalBorrows
    );

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(
        address payer,
        address onBehalfOf,
        uint256 repayAmount,
        uint256 accountBorrows,
        uint256 totalBorrows
    );

    /**
     * @notice Event emitted when the reserve factor is changed
     */
    event NewReserveFactor(
        uint256 oldReserveFactorMantissa, uint256 newReserveFactorMantissa
    );

    /**
     * @notice Event emitted when the max borrow rate is changed
     */
    event NewBorrowRateMax(
        uint256 oldBorrowRateMaxMantissa, uint256 newBorrowRateMaxMantissa
    );

    /**
     * @notice Event emitted when the seize share is changed
     */
    event NewProtocolSeizeShare(
        uint256 oldProtocolSeizeShareMantissa, uint256 newProtocolSeizeShareMantissa
    );

    /**
     * @notice Event emitted when interest is accrued
     */
    event AccrueInterest(
        uint256 cashPrior,
        uint256 totalReserves,
        uint256 borrowIndex,
        uint256 totalBorrows
    );

    /**
     * @notice Event emitted when a borrow is liquidated
     */
    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address pTokenCollateral,
        uint256 seizeTokens
    );

    /**
     * @notice Event emitted when the reserves are added
     */
    event ReservesAdded(address benefactor, uint256 addAmount, uint256 newTotalReserves);

    /**
     * @notice Event emitted when the reserves are reduced by protocol owner or governor
     */
    event ReservesReduced(address admin, uint256 reduceAmount, uint256 newTotalReserves);

    /**
     * @notice Event emitted when the reserves are reduced by emergency guardian
     */
    event EmergencyWithdrawn(
        address caller, uint256 reduceAmount, uint256 newTotalReserves
    );

    /**
     * @notice Sender supplies assets into the market and receives pTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param tokenAmount The amount of token to mint for supply
     * @param receiver User whom the supply will be attributed to
     * @return amount of supplied underlying asset
     */
    function mint(uint256 tokenAmount, address receiver) external returns (uint256);

    /**
     * @notice sender supplies assets into the market and minter receives pTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @param receiver User whom the supply will be attributed to
     * @return amount of minted tokens
     */
    function deposit(uint256 mintAmount, address receiver) external returns (uint256);

    /**
     * @notice Sender redeems pTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of pTokens to redeem into underlying
     * @param receiver The address to receive underlying redeemed asset
     * @param owner The address which account for redeem tokens
     * @return amount of redeemed underlying asset
     */
    function redeem(uint256 redeemTokens, address receiver, address owner)
        external
        returns (uint256);

    /**
     * @notice Sender redeems pTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @param receiver The address to receive underlying redeemed asset
     * @param owner The address which account for redeem tokens
     * @return amount of burnt tokens
     */
    function withdraw(uint256 redeemAmount, address receiver, address owner)
        external
        returns (uint256);

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrow(uint256 borrowAmount) external;

    /**
     * @notice Sender borrows assets on behalf of some other address. This function is only available
     *   for senders, explicitly marked as delegates of the borrower using `riskEngine.updateDelegate`
     * @param onBehalfOf The borrower, on behalf of whom to borrow
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrowOnBehalfOf(address onBehalfOf, uint256 borrowAmount) external;

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     */
    function repayBorrow(uint256 repayAmount) external;

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param onBehalfOf the account with the debt being payed off
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     */
    function repayBorrowOnBehalfOf(address onBehalfOf, uint256 repayAmount) external;

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this pToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param pTokenCollateral The market in which to seize collateral from the borrower
     */
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        IPToken pTokenCollateral
    ) external;

    /**
     * @notice Applies accrued interest to total borrows and reserves
     * @dev This calculates interest accrued from the last checkpointed timestamp
     *   up to the current timestamp and writes new checkpoint to storage.
     */
    function accrueInterest() external;

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Will fail unless called by another pToken during the process of liquidation.
     *  Its absolutely critical to use msg.sender as the borrowed pToken and not a parameter.
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of pTokens to seize
     */
    function seize(address liquidator, address borrower, uint256 seizeTokens) external;

    /**
     * @notice The sender adds to reserves.
     * @param addAmount The amount fo underlying token to add as reserves
     */
    function addReserves(uint256 addAmount) external;

    /// ***Admin Functions***

    /**
     * @notice accrues interest and sets a new reserve factor for the protocol
     * @dev Admin function to accrue interest and set a new reserve factor
     */
    function setReserveFactor(uint256 newReserveFactorMantissa) external;

    /**
     * @notice accrues interest and sets a new maximum borrow rate for pToken
     * @dev Admin function to accrue interest and set a new maximum borrow rate
     */
    function setBorrowRateMax(uint256 newBorrowRateMaxMantissa) external;

    /**
     * @notice sets a new seize share for the protocol
     * @dev Admin function to set a new seize share
     */
    function setProtocolSeizeShare(uint256 newProtocolSeizeShareMantissa) external;

    /**
     * @notice Accrues interest and reduces reserves by transferring to emergency guardian
     * @param reduceAmount Amount of reduction to total reserves
     */
    function reduceReservesEmergency(uint256 reduceAmount) external;

    /**
     * @notice Accrues interest and reduces reserves by transferring to protocol owner
     * @param reduceAmount Amount of reduction to owner reserves
     */
    function reduceReservesOwner(uint256 reduceAmount) external;

    /**
     * @notice Accrues interest and reduces reserves by transferring to governor
     * @param reduceAmount Amount of reduction to configurator reserves
     */
    function reduceReservesConfigurator(uint256 reduceAmount) external;

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract.
     * Tokens are sent to admin (timelock)
     * @param token The address of the ERC-20 token to sweep
     */
    function sweepToken(IERC20 token) external;

    /// ***Getter Functions***

    /**
     * @notice Return the latest max borrow rate
     */
    function borrowRateMaxMantissa() external view returns (uint256);

    /**
     * @notice Return the latest accrual timestamp of market
     */
    function accrualBlockTimestamp() external view returns (uint256);

    /**
     * @notice Return the up-to-date exchange rate with pending accrued interest
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() external view returns (uint256);

    /**
     * @notice Get the underlying balance of the `owner`
     * @dev This does not accrues interest and use pending accrued interest for calculation
     * @param owner The address of the account to query
     * @return The amount of underlying owned by `owner`
     */
    function balanceOfUnderlying(address owner) external view returns (uint256);

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by risk engine to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(address account)
        external
        view
        returns (uint256, uint256, uint256);

    /**
     * @notice Returns the current total borrows plus pending accrued interest
     * @return The total borrows with interest
     */
    function totalBorrowsCurrent() external view returns (uint256);

    /**
     * @notice Returns the current total reserves plus pending accrued interest
     * @return The total reserves with interest
     */
    function totalReservesCurrent() external view returns (uint256);

    /**
     * @notice Returns the current total remaing reserves plus
     * pending accrued interest for protocol owner
     * @return The total reserves with interest
     */
    function ownerReservesCurrent() external view returns (uint256);

    /**
     * @notice Returns the current total remaing reserves plus
     * pending accrued interest for configurator
     * @return The total reserves with interest
     */
    function configuratorReservesCurrent() external view returns (uint256);

    /**
     * @notice Calculate account's borrow balance using the pending updated borrowIndex
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceCurrent(address account) external view returns (uint256);

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceStored(address account) external view returns (uint256);

    /**
     * @notice Calculates the exchange rate from the underlying to the pToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view returns (uint256);

    /**
     * @notice Returns the initial exchange rate used for minting pTokens,
     *  calculated as 0.02 * 10^(18 + underlyingDecimals - pTokenDecimals)
     * @return The initial exchange rate of the pToken
     */
    function initialExchangeRate() external view returns (uint256);

    /**
     * @notice Get cash balance of this pToken in the underlying asset
     * @return The quantity of underlying asset owned by this contract
     */
    function getCash() external view returns (uint256);

    /**
     * @notice Returns the current per-second borrow interest rate for this pToken
     * @return The borrow interest rate per second, scaled by 1e18
     */
    function borrowRatePerSecond() external view returns (uint256);

    /**
     * @notice Returns the current per-second supply interest rate for this pToken
     * @return The supply interest rate per second, scaled by 1e18
     */
    function supplyRatePerSecond() external view returns (uint256);

    /**
     * @notice Returns the last updated total borrow without pending interest
     */
    function totalBorrows() external view returns (uint256);

    /**
     * @notice Returns the last updated total reserve without pending interest
     */
    function totalReserves() external view returns (uint256);

    /**
     * @notice Returns the last updated remaining reserves for protocol owner
     */
    function ownerReserves() external view returns (uint256);

    /**
     * @notice Returns the last updated remaining reserves for configurator
     */
    function configuratorReserves() external view returns (uint256);

    /**
     * @notice Returns the last stored borrow index
     */
    function borrowIndex() external view returns (uint256);

    /**
     * @notice Returns reserve factor mantissa
     */
    function reserveFactorMantissa() external view returns (uint256);

    /**
     * @notice Returns the risk engine contract
     */
    function riskEngine() external view returns (IRiskEngine);

    /**
     * @notice Returns the total supply
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Returns the pToken name
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the pToken symbol
     */
    function symbol() external view returns (string memory);

    /**
     * @notice Returns the pToken decimals
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the pToken underlying token address
     */
    function asset() external view returns (address);

    /**
     * @notice Returns the protocol seize share
     */
    function protocolSeizeShareMantissa() external view returns (uint256);

    /**
     * @notice Converts an underlying amount to the equivalent amount of pTokens
     * based on the current total supply and assets.
     * @dev calculate pToken per underlying, accounting for a zero total supply case.
     * @param assets The amount of underlying to convert to pTokens.
     * @return The equivalent amount of pTokens.
     */
    function convertToShares(uint256 assets) external view returns (uint256);

    /**
     * @notice Converts a pToken amount to the equivalent amount of underlying
     * based on the current total supply and assets.
     * @dev calculate underlying per pToken, accounting for a zero total supply case.
     * @param shares The amount of pTokens to convert to underlying.
     * @return The equivalent amount of underlying.
     */
    function convertToAssets(uint256 shares) external view returns (uint256);

    /**
     * @notice Returns the maximum number of pTokens that can be minted for a given receiver,
     * based on the current exchange rate.
     * @param receiver The address for which pTokens are being minted.
     * @return The maximum amount of pTokens that can be minted for the receiver.
     */
    function maxMint(address receiver) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of underlying that can be deposited,
     * considering the risk engine’s mint allowance and any supply cap.
     * @param account The address for which assets are being deposited (unused in this implementation).
     * @return The maximum deposit amount, based on mint allowance and any supply cap.
     */
    function maxDeposit(address account) external view returns (uint256);

    /**
     * @notice Returns the maximum number of pTokens that can be redeemed by an account owner,
     * based on current exchange rate and risk limits.
     * @param owner The address of the account from which pTokens are redeemed.
     * @return maxShares The maximum amount of pTokens that can be redeemed by the owner.
     */
    function maxRedeem(address owner) external view returns (uint256 maxShares);

    /**
     * @notice Returns the maximum amount of underlying can be withdrawn by owner,
     * based on risk engine limits.
     * @param owner The address of the account from which underlying are withdrawn.
     * @return The maximum amount of underlying that can be withdrawn by owner.
     */
    function maxWithdraw(address owner) external view returns (uint256);

    /**
     * @notice Returns the actual amount of pTokens that would be minted
     * for a given underlying amount if deposited.
     * @param assets The amount of underlying assets to deposit.
     * @return shares The calculated amount of pTokens corresponding to the deposit.
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Calculates the actual amount of underlying assets required
     * to mint a given amount of pTokens.
     * @param shares The number of pTokens to mint.
     * @return assets The required amount of underlying for minting the specified pTokens.
     */
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Calculates the actual number of pTokens required
     * to withdraw a specified amount of underlying.
     * @param assets The desired amount of underlying to withdraw.
     * @return shares The pTokens needed to facilitate the withdrawal of the underlying.
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Determines the actual amount of underlying redeemable for a given amount of pTokens.
     * @param shares The number of pTokens to redeem.
     * @return assets The equivalent amount of underlying for the redeemed pTokens.
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Returns the total amount of underlying assets managed by the protocol,
     * including underlying balance, borrows, and reserves with accruing interests.
     * @return The total supplied assets,
     * calculated as cash plus total borrows minus total reserves.
     */
    function totalAssets() external view returns (uint256);
}
