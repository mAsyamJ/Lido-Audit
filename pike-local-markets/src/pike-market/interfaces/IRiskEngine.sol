// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPToken} from "@interfaces/IPToken.sol";
import {RiskEngineError} from "@errors/RiskEngineError.sol";

interface IRiskEngine {
    struct BaseConfiguration {
        //  Multiplier representing the most one can borrow against their collateral in this market.
        //  For instance, 0.9 to allow borrowing 90% of collateral value.
        //  Must be between 0 and 1, and stored as a mantissa.
        uint256 collateralFactorMantissa;
        //  Multiplier representing the collateralization after which the borrow is eligible
        //  for liquidation. For instance, 0.8 liquidate when the borrow is 80% of collateral
        //  value. Must be between 0 and collateral factor, stored as a mantissa.
        uint256 liquidationThresholdMantissa;
        // Multiplier representing the discount on collateral that a liquidator receives
        uint256 liquidationIncentiveMantissa;
    }

    /// @notice Emitted when new configuration set for e-mode
    event NewEModeConfiguration(
        uint8 categoryId, BaseConfiguration oldConfig, BaseConfiguration newConfig
    );

    /// @notice Emitted when new configuration set for e-mode
    event NewMarketConfiguration(
        IPToken pToken, BaseConfiguration oldConfig, BaseConfiguration newConfig
    );

    /// @notice Emitted when a new oracle engine is set
    event NewOracleEngine(address oldOracleEngine, address newOracleEngine);

    /// @notice Emitted when reserve share percentages are updated
    event NewReserveShares(
        uint256 newOwnerShareMantissa, uint256 newConfiguratorShareMantissa
    );

    /// @notice Emitted when an admin supports a market
    event MarketListed(IPToken pToken);

    /// @notice Emitted when user switch e-mode
    event EModeSwitched(address account, uint8 oldCategory, uint8 newCategory);

    /// @notice Emitted when an emode status is updated
    event EModeUpdated(
        uint8 categoryId,
        address pToken,
        bool allowed,
        bool collateralStatus,
        bool borrowStatus
    );

    /// @notice Emitted when an account enters a market
    event MarketEntered(IPToken pToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(IPToken pToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(
        address indexed pToken,
        uint256 oldCloseFactorMantissa,
        uint256 newCloseFactorMantissa
    );

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(IPToken indexed pToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a pToken is changed
    event NewBorrowCap(IPToken indexed pToken, uint256 newBorrowCap);

    /// @notice Emitted when supply cap for a pToken is changed
    event NewSupplyCap(IPToken indexed pToken, uint256 newSupplyCap);

    /// @notice Emitted when the borrowing or redeeming delegate rights are updated for an account
    event DelegateUpdated(
        address indexed approver, address indexed delegate, bool approved
    );

    /**
     * @notice Updates the reserve share percentages for the owner and configurator that applies
     * to all ptokens.
     * @dev needs protocol owner access to update
     * @param newOwnerShareMantissa The new share of reserve percentage for the owner (scaled by 1e18).
     * @param newConfiguratorShareMantissa The new share of reserve percentage for the configurator (scaled by 1e18).
     */
    function setReserveShares(
        uint256 newOwnerShareMantissa,
        uint256 newConfiguratorShareMantissa
    ) external;

    /**
     * @notice Switch caller E-Mode category
     * @dev 0 is initial and default category for all markets
     * @dev caller should met the requirements for new category to join, meaning
     * all user collateral and borrow should met new category supported assets
     * @param newCategoryId The new e-mode category that caller wants to switch
     */
    function switchEMode(uint8 newCategoryId) external;

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param pTokens The list of addresses of the pToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(address[] memory pTokens) external returns (uint256[] memory);

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param pTokenAddress The address of the asset to be removed
     */
    function exitMarket(address pTokenAddress) external;

    /**
     * @notice Grants or revokes the borrowing or redeeming delegate rights to / from an account
     *  If allowed, the delegate will be able to borrow funds on behalf of the sender
     *  Upon a delegated borrow, the delegate will receive the funds, and the borrower
     *  will see the debt on their account
     *  Upon a delegated redeem, the delegate will receive the redeemed amount and the approver
     *  will see a deduction in his pToken balance
     * @param delegate The address to update the rights for
     * @param approved Whether to grant (true) or revoke (false) the borrowing or redeeming rights
     */
    function updateDelegate(address delegate, bool approved) external;

    /// *** Hooks ***

    /**
     * @notice Enables collateral for an account if it previously had no balance of the pToken.
     * @dev This function is called only by listed pTokens during the mint process.
     * @param account The address of the account for which collateral will be enabled.
     */
    function mintVerify(address account) external;

    /**
     * @notice Checks the account should borrow status after repaying debt
     * @dev If there is no debt remaining it removes borrow status for account
     * @param pToken The market to verify the repayment against
     * @param account The address of account that debt was repaid
     */
    function repayBorrowVerify(IPToken pToken, address account) external;

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param pToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise an error code (See Errors)
     */
    function borrowAllowed(address pToken, address borrower, uint256 borrowAmount)
        external
        returns (RiskEngineError.Error);

    /// *** Admin Functions ***

    /**
     * @notice Sets the oracle engine for a the risk engine
     * @dev Admin function to set oracle
     * @param newOracle The address of the new oracle
     */
    function setOracle(address newOracle) external;

    /**
     * @notice Set new risk params for specified e-mode
     * @dev Admin function to configure
     * @param categoryId the id of e-mode to modify
     * @param baseConfig the struct including collateralFactor, liqThreshold and liqIncentive
     */
    function configureEMode(uint8 categoryId, BaseConfiguration calldata baseConfig)
        external;

    /**
     * @notice Sets the closeFactor for a market used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param pTokenAddress address of ptoken set close factor for
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     */
    function setCloseFactor(address pTokenAddress, uint256 newCloseFactorMantissa)
        external;

    /**
     * @notice Sets the collateralFactor and liquidation threshold for a market
     * @dev Admin function to set per-market collateralFactor
     * @param baseConfig The collateralFactor, liqThreshold and liqIncentive of market
     */
    function configureMarket(IPToken pToken, BaseConfiguration calldata baseConfig)
        external;

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param pToken The address of the market (token) to list
     */
    function supportMarket(IPToken pToken) external;

    /**
     * @notice Add the e-mode and configure its status with amdin access
     * @param categoryId Id representing e-mode identifier
     * @param isAllowed The identifier to active or deactivate e-mode
     * @param pTokens The array of addresses to add to e-mode
     * @param collateralPermissions The array of collateral status for pTokens in e-mode
     * @param borrowPermissions The array of borrowable status for pTokens in e-mode
     */
    function supportEMode(
        uint8 categoryId,
        bool isAllowed,
        address[] calldata pTokens,
        bool[] calldata collateralPermissions,
        bool[] calldata borrowPermissions
    ) external;

    /**
     * @notice Set the given borrow caps for the given pToken markets.
     * Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev borrowCapGuardian function to set the borrow caps.
     * A borrow cap of type(uint256).max corresponds to unlimited borrowing.
     * @param pTokens The addresses of the markets (ptokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set.
     * A value of type(uint256).max corresponds to unlimited borrowing.
     */
    function setMarketBorrowCaps(
        IPToken[] calldata pTokens,
        uint256[] calldata newBorrowCaps
    ) external;

    /**
     * @notice Set the given supply caps for the given pToken markets.
     * Supplying that brings total supply to or above supply cap will revert.
     * @dev supplyCapGuardian function to set the supply caps.
     * A supply cap of type(uint256).max corresponds to unlimited supplying.
     * @param pTokens The addresses of the markets (ptokens) to change the supply caps for
     * @param newSupplyCaps The new supply cap values in underlying to be set.
     * A value of type(uint256).max corresponds to unlimited supplying.
     */
    function setMarketSupplyCaps(
        IPToken[] calldata pTokens,
        uint256[] calldata newSupplyCaps
    ) external;

    /**
     * @notice Admin function to pause mint
     */
    function setMintPaused(IPToken pToken, bool state) external returns (bool);

    /**
     * @notice Admin function to pause borrow
     */
    function setBorrowPaused(IPToken pToken, bool state) external returns (bool);

    /**
     * @notice Admin function to pause transfer
     */
    function setTransferPaused(bool state) external returns (bool);

    /**
     * @notice Admin function to pause sieze
     */
    function setSeizePaused(bool state) external returns (bool);

    /// ***Getter Functions***

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (IPToken[] memory);

    /**
     * @notice Retrieves the reserve shares for the protocol owner and configurator (governor).
     * @dev These shares represent the percentage of accumulated reserves allocated to the protocol owner
     * and configurator across all pTokens. Shares are expressed as mantissa values (scaled by 1e18)
     * @return ownerShareMantissa The percentage of accumulated total reserves for protocol owner
     * @return configuratorShareMantissa The percentage of accumulated total reserves for configurator
     */
    function getReserveShares()
        external
        view
        returns (uint256 ownerShareMantissa, uint256 configuratorShareMantissa);

    /**
     * @notice Returns whether the given account is entered (enabled as collateral)
     * in the given asset
     * @param account The address of the account to check
     * @param pToken The pToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkCollateralMembership(address account, IPToken pToken)
        external
        view
        returns (bool);

    /**
     * @notice Returns whether the given account has borrow position
     * in the given asset
     * @param account The address of the account to check
     * @param pToken The pToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkBorrowMembership(address account, IPToken pToken)
        external
        view
        returns (bool);

    /**
     * @notice Returns the active category of account
     * @param account The address of the account to check
     * @return Category Id "0" for default and non zero for e-mode
     */
    function accountCategory(address account) external view returns (uint8);

    /**
     * @notice Determine the current account liquidity with respect to liquidation threshold
     * @return (possible error code,
     *             account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account)
        external
        view
        returns (RiskEngineError.Error, uint256, uint256);

    /**
     * @notice Determine the current account liquidity with respect to collateral factor
     * @return (possible error code,
     *             account liquidity in excess of borrow collateral requirements,
     *          account shortfall below borrow collateral requirements)
     */
    function getAccountBorrowLiquidity(address account)
        external
        view
        returns (RiskEngineError.Error, uint256, uint256);

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     *  with respect to collateral factor
     * @param pTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code,
     *             hypothetical account liquidity in excess of borrow collateral requirements,
     *          hypothetical account shortfall below borrow collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address pTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (RiskEngineError.Error, uint256, uint256);

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in pToken.liquidateBorrowFresh)
     * @param borrower The address of borrower
     * @param pTokenBorrowed The address of the borrowed pToken
     * @param pTokenCollateral The address of the collateral pToken
     * @param actualRepayAmount The amount of pTokenBorrowed underlying to convert into pTokenCollateral tokens
     * @return (errorCode, number of pTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(
        address borrower,
        address pTokenBorrowed,
        address pTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (RiskEngineError.Error, uint256);

    /**
     * @notice Checks if a delegate has been approved by a user for all markets.
     * @param user The address of the user who may have approved a delegatee.
     * @param delegate The address of the delegatee to check for approval.
     * @return True if the delegate is approved by the user, false otherwise.
     */
    function delegateAllowed(address user, address delegate)
        external
        view
        returns (bool);

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() external view returns (IPToken[] memory);

    /**
     * @notice Returns true if the given pToken market has been deprecated
     * @dev All borrows in a deprecated pToken market can be immediately liquidated
     * @param pToken The market to check if deprecated
     */
    function isDeprecated(IPToken pToken) external view returns (bool);

    /**
     * @notice Returns the maximum amount of underlying tokens that can be withdrawn
     * from a PToken contract for a given account.
     * @dev Returns zero if there’s a price error, insufficient liquidity,
     * or if the market is not listed.
     * @param pToken The PToken contract address to check withdrawal limits.
     * @param account The account address for which to check withdrawal capacity.
     * @return The maximum amount of underlying tokens that can be withdrawn.
     */
    function maxWithdraw(address pToken, address account)
        external
        view
        returns (uint256);

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param account The address of account try to mint
     * @param pToken The market to verify the mint against
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise an error code (See Errors)
     */
    function mintAllowed(address account, address pToken, uint256 mintAmount)
        external
        view
        returns (RiskEngineError.Error);

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param pToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of pTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise an error code (See Errors)
     */
    function redeemAllowed(address pToken, address redeemer, uint256 redeemTokens)
        external
        view
        returns (RiskEngineError.Error);

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param pToken The market to verify the repay against
     * @return 0 if the repay is allowed, otherwise an error code (See Errors)
     */
    function repayBorrowAllowed(address pToken)
        external
        view
        returns (RiskEngineError.Error);

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address pTokenBorrowed,
        address pTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external view returns (RiskEngineError.Error);

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @return 0 if the borrow is allowed, otherwise an error code (See Errors)
     */
    function seizeAllowed(address pTokenCollateral, address pTokenBorrowed)
        external
        view
        returns (RiskEngineError.Error);

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param pToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param transferTokens The number of pTokens to transfer
     * @return 0 if the transfer is allowed, otherwise an error code (See Errors)
     */
    function transferAllowed(address pToken, address src, uint256 transferTokens)
        external
        view
        returns (RiskEngineError.Error);

    /**
     * @return the oracle engine address
     */
    function oracle() external view returns (address);

    /**
     * @notice return the collateral factor of a pToken in category
     * @param categoryId identifier for the category (0 for default and non zero for e-mode)
     * @param pToken address of asset to check
     */
    function collateralFactor(uint8 categoryId, IPToken pToken)
        external
        view
        returns (uint256);

    /**
     * @notice return the liquidation threshold of a pToken in category
     * @param categoryId identifier for the category (0 for default and non zero for e-mode)
     * @param pToken address of asset to check
     */
    function liquidationThreshold(uint8 categoryId, IPToken pToken)
        external
        view
        returns (uint256);

    /**
     * @notice return the liquidation incentive of a pToken in category
     * @param categoryId identifier for the category (0 for default and non zero for e-mode)
     * @param pToken address of asset to check
     */
    function liquidationIncentive(uint8 categoryId, address pToken)
        external
        view
        returns (uint256);

    /**
     * @return the close factor percentage for liquidation
     */
    function closeFactor(address pToken) external view returns (uint256);

    /**
     * @return the supply cap for the pToken
     */
    function supplyCap(address pToken) external view returns (uint256);

    /**
     * @return the borrow cap for the pToken
     */
    function borrowCap(address pToken) external view returns (uint256);

    /**
     * @notice Retrieves the list of supported markets in a specific eMode category.
     *  Separates the markets into those supported as collateral and those supported as borrowable assets.
     * @dev Iterates through all markets, checking their eligibility as collateral or borrowable assets
     *  based on the specified eMode category.
     * @param categoryId The ID of the eMode category.
     * @return collateralTokens An array of token addresses supported as collateral in eMode.
     * @return borrowTokens An array of token addresses supported as borrowable assets in specified eMode.
     */
    function emodeMarkets(uint8 categoryId)
        external
        view
        returns (address[] memory collateralTokens, address[] memory borrowTokens);
}
