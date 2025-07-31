//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRiskEngine, RiskEngineError} from "@interfaces/IRiskEngine.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {RiskEngineStorage} from "@storage/RiskEngineStorage.sol";
import {ExponentialNoError} from "@utils/ExponentialNoError.sol";
import {CommonError} from "@errors/CommonError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";
import {RBACMixin} from "@utils/RBACMixin.sol";

/**
 * @title Pike Markets RiskEngine Contract
 * @author NUTS Finance (hello@pike.finance)
 */
contract RiskEngineModule is IRiskEngine, RiskEngineStorage, OwnableMixin, RBACMixin {
    using ExponentialNoError for ExponentialNoError.Exp;
    using ExponentialNoError for uint256;

    /**
     * @inheritdoc IRiskEngine
     */
    function setOracle(address newOracle) external {
        checkPermissionOrAdmin(_PROTOCOL_OWNER_PERMISSION, msg.sender);
        require(newOracle != address(0), CommonError.ZeroAddress());

        RiskEngineData storage $ = _getRiskEngineStorage();
        emit NewOracleEngine($.oracle, newOracle);
        $.oracle = newOracle;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setReserveShares(
        uint256 newOwnerShareMantissa,
        uint256 newConfiguratorShareMantissa
    ) external {
        checkPermissionOrAdmin(_PROTOCOL_OWNER_PERMISSION, msg.sender);
        // both can not exceed 100% of totalReserve
        require(
            newOwnerShareMantissa + newConfiguratorShareMantissa <= _MANTISSA_ONE,
            RiskEngineError.InvalidReserveShare()
        );

        RiskEngineData storage $ = _getRiskEngineStorage();
        $.ownerShareMantissa = newOwnerShareMantissa;
        $.configuratorShareMantissa = newConfiguratorShareMantissa;
        emit NewReserveShares(newOwnerShareMantissa, newConfiguratorShareMantissa);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setCloseFactor(address pTokenAddress, uint256 newCloseFactorMantissa)
        external
    {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        require(
            newCloseFactorMantissa <= _MANTISSA_ONE, RiskEngineError.InvalidCloseFactor()
        );

        RiskEngineData storage $ = _getRiskEngineStorage();
        uint256 oldCloseFactorMantissa = $.closeFactorMantissa[pTokenAddress];
        $.closeFactorMantissa[pTokenAddress] = newCloseFactorMantissa;
        emit NewCloseFactor(pTokenAddress, oldCloseFactorMantissa, newCloseFactorMantissa);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function configureMarket(IPToken pToken, BaseConfiguration calldata baseConfig)
        external
    {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        RiskEngineData storage $ = _getRiskEngineStorage();
        // Verify market is listed
        require($.markets[address(pToken)].isListed, RiskEngineError.MarketNotListed());

        // Check collateral factor <= 0.9
        require(
            baseConfig.collateralFactorMantissa.toExp().lessThanOrEqualExp(
                _COLLATERAL_FACTOR_MAX_MANTISSA.toExp()
            ),
            RiskEngineError.InvalidCollateralFactor()
        );

        require(
            baseConfig.liquidationIncentiveMantissa >= _MANTISSA_ONE,
            RiskEngineError.InvalidIncentiveThreshold()
        );

        // Ensure that liquidation threshold <= 1
        require(
            baseConfig.liquidationThresholdMantissa <= _MANTISSA_ONE,
            RiskEngineError.InvalidLiquidationThreshold()
        );

        // Ensure that liquidation threshold >= CF
        require(
            baseConfig.liquidationThresholdMantissa >= baseConfig.collateralFactorMantissa,
            RiskEngineError.InvalidLiquidationThreshold()
        );

        BaseConfiguration memory oldConfiguration =
            $.markets[address(pToken)].baseConfiguration;
        BaseConfiguration storage baseConfiguration =
            $.markets[address(pToken)].baseConfiguration;

        // write new values
        baseConfiguration.collateralFactorMantissa = baseConfig.collateralFactorMantissa;
        baseConfiguration.liquidationThresholdMantissa =
            baseConfig.liquidationThresholdMantissa;
        baseConfiguration.liquidationIncentiveMantissa =
            baseConfig.liquidationIncentiveMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewMarketConfiguration(pToken, oldConfiguration, baseConfig);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function supportMarket(IPToken pToken) external {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        require(address(pToken) != address(0), CommonError.ZeroAddress());

        RiskEngineData storage $ = _getRiskEngineStorage();
        require(!$.markets[address(pToken)].isListed, RiskEngineError.AlreadyListed());

        Market storage newMarket = $.markets[address(pToken)];
        newMarket.isListed = true;
        delete newMarket.baseConfiguration;

        _addMarketInternal(address(pToken));

        emit MarketListed(pToken);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function supportEMode(
        uint8 categoryId,
        bool isAllowed,
        address[] calldata pTokens,
        bool[] calldata collateralPermissions,
        bool[] calldata borrowPermissions
    ) external {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        RiskEngineData storage $ = _getRiskEngineStorage();

        uint256 length = pTokens.length;
        // not allowed to configure default category
        require(categoryId != 0, RiskEngineError.InvalidCategory());

        require(
            length == collateralPermissions.length && length == borrowPermissions.length,
            CommonError.NoArrayParity()
        );

        for (uint256 i = 0; i < length; i++) {
            require($.markets[pTokens[i]].isListed, RiskEngineError.NotListed());

            EModeConfiguration storage newEMode = $.emodes[categoryId];
            newEMode.allowed = isAllowed;
            delete newEMode.baseConfiguration;

            $.collateralCategory[categoryId][pTokens[i]] = collateralPermissions[i];
            $.borrowCategory[categoryId][pTokens[i]] = borrowPermissions[i];

            emit EModeUpdated(
                categoryId,
                pTokens[i],
                isAllowed,
                collateralPermissions[i],
                borrowPermissions[i]
            );
        }
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function configureEMode(uint8 categoryId, BaseConfiguration calldata baseConfig)
        external
    {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        RiskEngineData storage $ = _getRiskEngineStorage();

        // can not be default category or not allowed category
        require(
            categoryId != 0 && $.emodes[categoryId].allowed,
            RiskEngineError.InvalidCategory()
        );

        require(
            baseConfig.liquidationIncentiveMantissa >= _MANTISSA_ONE,
            RiskEngineError.InvalidIncentiveThreshold()
        );

        // Ensure that liquidation threshold <= 1
        require(
            baseConfig.liquidationThresholdMantissa <= _MANTISSA_ONE,
            RiskEngineError.InvalidLiquidationThreshold()
        );

        // Ensure that liquidation threshold >= CF
        require(
            baseConfig.liquidationThresholdMantissa >= baseConfig.collateralFactorMantissa,
            RiskEngineError.InvalidLiquidationThreshold()
        );

        BaseConfiguration memory oldConfiguration = $.emodes[categoryId].baseConfiguration;
        BaseConfiguration storage baseConfiguration =
            $.emodes[categoryId].baseConfiguration;

        // write new values
        baseConfiguration.collateralFactorMantissa = baseConfig.collateralFactorMantissa;
        baseConfiguration.liquidationThresholdMantissa =
            baseConfig.liquidationThresholdMantissa;
        baseConfiguration.liquidationIncentiveMantissa =
            baseConfig.liquidationIncentiveMantissa;

        emit NewEModeConfiguration(categoryId, oldConfiguration, baseConfig);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setMarketBorrowCaps(
        IPToken[] calldata pTokens,
        uint256[] calldata newBorrowCaps
    ) external {
        checkPermission(_BORROW_CAP_GUARDIAN_PERMISSION, msg.sender);
        uint256 numMarkets = pTokens.length;
        uint256 numBorrowCap = newBorrowCaps.length;

        require(
            numMarkets == numBorrowCap && numMarkets != 0, CommonError.NoArrayParity()
        );

        for (uint256 i = 0; i < numMarkets; ++i) {
            _getRiskEngineStorage().borrowCaps[address(pTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(pTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setMarketSupplyCaps(
        IPToken[] calldata pTokens,
        uint256[] calldata newSupplyCaps
    ) external {
        checkPermission(_SUPPLY_CAP_GUARDIAN_PERMISSION, msg.sender);
        uint256 numMarkets = pTokens.length;
        uint256 newSupplyCap = newSupplyCaps.length;

        require(
            numMarkets == newSupplyCap && numMarkets != 0, CommonError.NoArrayParity()
        );

        for (uint256 i; i < numMarkets; ++i) {
            _getRiskEngineStorage().supplyCaps[address(pTokens[i])] = newSupplyCaps[i];
            emit NewSupplyCap(pTokens[i], newSupplyCaps[i]);
        }
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setMintPaused(IPToken pToken, bool state) external returns (bool) {
        checkPermission(_PAUSE_GUARDIAN_PERMISSION, msg.sender);
        RiskEngineData storage $ = _getRiskEngineStorage();

        require($.markets[address(pToken)].isListed, RiskEngineError.MarketNotListed());

        $.mintGuardianPaused[address(pToken)] = state;
        emit ActionPaused(pToken, "Mint", state);
        return state;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setBorrowPaused(IPToken pToken, bool state) external returns (bool) {
        checkPermission(_PAUSE_GUARDIAN_PERMISSION, msg.sender);
        RiskEngineData storage $ = _getRiskEngineStorage();
        require($.markets[address(pToken)].isListed, RiskEngineError.MarketNotListed());

        $.borrowGuardianPaused[address(pToken)] = state;
        emit ActionPaused(pToken, "Borrow", state);
        return state;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setTransferPaused(bool state) external returns (bool) {
        checkPermission(_PAUSE_GUARDIAN_PERMISSION, msg.sender);
        _getRiskEngineStorage().transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setSeizePaused(bool state) external returns (bool) {
        checkPermission(_PAUSE_GUARDIAN_PERMISSION, msg.sender);
        _getRiskEngineStorage().seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function switchEMode(uint8 newCategoryId) external {
        RiskEngineData storage $ = _getRiskEngineStorage();

        uint8 category = $.accountCategory[msg.sender];

        // can not swtich if already in e-mode
        require(category != newCategoryId, RiskEngineError.AlreadyInEMode());
        // checks if collateral and borrow category of e-mdoe match the user assets
        // for default category all assets are allowed for collateral and borrow
        if (newCategoryId != 0) {
            // can not swtich if not allowed
            require($.emodes[newCategoryId].allowed, RiskEngineError.InvalidCategory());
            // For each asset the account is in
            IPToken[] memory assets = $.accountAssets[msg.sender];
            for (uint256 i = 0; i < assets.length; i++) {
                require(
                    !$.markets[address(assets[i])].collateralMembership[msg.sender]
                        || $.collateralCategory[newCategoryId][address(assets[i])],
                    RiskEngineError.InvalidCollateralStatus(address(assets[i]))
                );
                require(
                    !$.markets[address(assets[i])].borrowMembership[msg.sender]
                        || $.borrowCategory[newCategoryId][address(assets[i])],
                    RiskEngineError.InvalidBorrowStatus(address(assets[i]))
                );
            }
        }
        // to switch e-mode we check if new category risk params create shortfall
        (RiskEngineError.Error err,, uint256 shortfall) =
        getHypotheticalAccountLiquidityInternal(
            msg.sender, IPToken(address(0)), newCategoryId, 0, 0, _getCollateralFactor
        );
        require(
            err == RiskEngineError.Error.NO_ERROR,
            RiskEngineError.SwitchEMode(uint256(err))
        );
        require(
            shortfall == 0,
            RiskEngineError.SwitchEMode(
                uint256(RiskEngineError.Error.INSUFFICIENT_LIQUIDITY)
            )
        );

        //update user category
        $.accountCategory[msg.sender] = newCategoryId;

        emit EModeSwitched(msg.sender, category, newCategoryId);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function enterMarkets(address[] memory pTokens) external returns (uint256[] memory) {
        uint256 len = pTokens.length;

        uint256[] memory results = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            IPToken pToken = IPToken(pTokens[i]);

            results[i] = uint256(addToMarketCollateralInternal(pToken, msg.sender));
        }

        return results;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function exitMarket(address pTokenAddress) external {
        IPToken pToken = IPToken(pTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the pToken */
        (uint256 tokensHeld, uint256 amountOwed,) = pToken.getAccountSnapshot(msg.sender);

        /* Fail if the sender is not permitted to redeem all of their tokens */
        RiskEngineError.Error allowed =
            redeemAllowedInternal(pTokenAddress, msg.sender, tokensHeld);
        require(
            allowed == RiskEngineError.Error.NO_ERROR,
            RiskEngineError.ExitMarketRedeemRejection(uint256(allowed))
        );

        Market storage marketToExit = _getRiskEngineStorage().markets[pTokenAddress];

        /* Return early if the sender is not already ‘in’ the market as collateral */
        if (!marketToExit.collateralMembership[msg.sender]) {
            return;
        }

        /* Set pToken account membership to false */
        delete marketToExit.collateralMembership[msg.sender];

        /* Delete pToken from the account’s list of assets if not borrowed */
        if (amountOwed == 0) {
            // load into memory for faster iteration
            IPToken[] memory userAssetList =
                _getRiskEngineStorage().accountAssets[msg.sender];
            uint256 len = userAssetList.length;
            uint256 assetIndex = len;
            for (uint256 i = 0; i < len; i++) {
                if (userAssetList[i] == pToken) {
                    assetIndex = i;
                    break;
                }
            }

            // We *must* have found the asset in the list or our redundant data structure is broken
            assert(assetIndex < len);

            // copy last item in list to location of item to be removed, reduce length by 1
            IPToken[] storage storedList =
                _getRiskEngineStorage().accountAssets[msg.sender];
            storedList[assetIndex] = storedList[storedList.length - 1];
            storedList.pop();
        }

        emit MarketExited(pToken, msg.sender);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function updateDelegate(address delegate, bool approved) external {
        require(delegate != address(0), CommonError.ZeroAddress());
        RiskEngineData storage $ = _getRiskEngineStorage();

        require(
            $.approvedDelegates[msg.sender][delegate] != approved,
            RiskEngineError.DelegationStatusUnchanged()
        );

        $.approvedDelegates[msg.sender][delegate] = approved;
        emit DelegateUpdated(msg.sender, delegate, approved);
    }

    /// *** Hooks ***

    /**
     * @inheritdoc IRiskEngine
     */
    function mintVerify(address account) external {
        addToMarketCollateralInternal(IPToken(msg.sender), account);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function repayBorrowVerify(IPToken pToken, address account) external {
        /* Get sender tokensHeld and amountOwed underlying from the pToken */
        (, uint256 amountOwed,) = pToken.getAccountSnapshot(account);
        RiskEngineData storage $ = _getRiskEngineStorage();

        if (amountOwed == 0) {
            delete $.markets[address(pToken)].borrowMembership[account];
            /* Delete pToken from the account’s list of assets if not enabled as collateral */
            if (!$.markets[address(pToken)].collateralMembership[account]) {
                // load into memory for faster iteration
                IPToken[] memory userAssetList = $.accountAssets[account];
                uint256 len = userAssetList.length;
                uint256 assetIndex = len;
                for (uint256 i = 0; i < len; i++) {
                    if (userAssetList[i] == pToken) {
                        assetIndex = i;
                        break;
                    }
                }

                // We *must* have found the asset in the list or our redundant data structure is broken
                assert(assetIndex < len);

                // copy last item in list to location of item to be removed, reduce length by 1
                IPToken[] storage storedList = $.accountAssets[account];
                storedList[assetIndex] = storedList[storedList.length - 1];
                storedList.pop();
            }
        }
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function borrowAllowed(address pToken, address borrower, uint256 borrowAmount)
        external
        returns (RiskEngineError.Error)
    {
        RiskEngineData storage $ = _getRiskEngineStorage();

        require(!$.borrowGuardianPaused[pToken], RiskEngineError.BorrowPaused());

        if (!$.markets[pToken].isListed) {
            return RiskEngineError.Error.MARKET_NOT_LISTED;
        }

        uint8 category = $.accountCategory[borrower];
        // Should check if account is in emode and pToken is allowed
        if (category != 0) {
            if (!$.borrowCategory[category][pToken] || !$.emodes[category].allowed) {
                return RiskEngineError.Error.NOT_ALLOWED_TO_BORROW;
            }
        }

        if (!$.markets[pToken].borrowMembership[borrower]) {
            // only pTokens may call borrowAllowed if borrower not in market
            require(msg.sender == pToken, RiskEngineError.SenderNotPToken());

            // attempt to add borrower to the market
            // already checked if market is listed
            addToMarketBorrowInternal(IPToken(msg.sender), borrower);

            // it should be impossible to break the important invariant
            assert($.markets[pToken].borrowMembership[borrower]);
        }

        if (IOracleEngine($.oracle).getUnderlyingPrice(IPToken(pToken)) == 0) {
            return RiskEngineError.Error.PRICE_ERROR;
        }

        uint256 cap = $.borrowCaps[pToken];
        // Borrow cap of type(uint256).max corresponds to unlimited borrowing
        if (cap != type(uint256).max) {
            uint256 totalBorrows = IPToken(pToken).totalBorrows();
            uint256 nextTotalBorrows = totalBorrows.add_(borrowAmount);
            if (nextTotalBorrows > cap) {
                return RiskEngineError.Error.BORROW_CAP_EXCEEDED;
            }
        }

        (RiskEngineError.Error err,, uint256 shortfall) =
        getHypotheticalAccountLiquidityInternal(
            borrower,
            IPToken(pToken),
            $.accountCategory[borrower],
            0,
            borrowAmount,
            _getCollateralFactor
        );
        if (err != RiskEngineError.Error.NO_ERROR) {
            return err;
        }
        if (shortfall > 0) {
            return RiskEngineError.Error.INSUFFICIENT_LIQUIDITY;
        }

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function mintAllowed(address account, address pToken, uint256 mintAmount)
        external
        view
        returns (RiskEngineError.Error)
    {
        RiskEngineData storage $ = _getRiskEngineStorage();

        // Pausing is a very serious situation - we revert to sound the alarms
        require(!$.mintGuardianPaused[pToken], RiskEngineError.MintPaused());

        if (!$.markets[pToken].isListed) {
            return RiskEngineError.Error.MARKET_NOT_LISTED;
        }

        uint8 category = $.accountCategory[account];
        // Should check if account is in emode and pToken is allowed
        if (category != 0 && !$.emodes[category].allowed) {
            return RiskEngineError.Error.EMODE_NOT_ALLOWED;
        }

        uint256 cap = $.supplyCaps[pToken];
        // Skipping the cap check for uncapped coins to save some gas
        if (cap != type(uint256).max) {
            uint256 pTokenSupply = IPToken(pToken).totalSupply();

            uint256 nextTotalSupply = IPToken(pToken).exchangeRateStored().toExp()
                .mul_ScalarTruncateAddUInt(pTokenSupply, mintAmount);
            if (nextTotalSupply > cap) {
                return RiskEngineError.Error.SUPPLY_CAP_EXCEEDED;
            }
        }

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function redeemAllowed(address pToken, address redeemer, uint256 redeemTokens)
        external
        view
        returns (RiskEngineError.Error)
    {
        RiskEngineError.Error allowed =
            redeemAllowedInternal(pToken, redeemer, redeemTokens);
        if (allowed != RiskEngineError.Error.NO_ERROR) {
            return allowed;
        }

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function repayBorrowAllowed(address pToken)
        external
        view
        returns (RiskEngineError.Error)
    {
        if (!_getRiskEngineStorage().markets[pToken].isListed) {
            return RiskEngineError.Error.MARKET_NOT_LISTED;
        }

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function liquidateBorrowAllowed(
        address pTokenBorrowed,
        address pTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external view returns (RiskEngineError.Error) {
        RiskEngineData storage $ = _getRiskEngineStorage();

        if (!$.markets[pTokenBorrowed].isListed || !$.markets[pTokenCollateral].isListed)
        {
            return RiskEngineError.Error.MARKET_NOT_LISTED;
        }

        uint256 borrowBalance = IPToken(pTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        if (isDeprecated(IPToken(pTokenBorrowed))) {
            require(borrowBalance >= repayAmount, RiskEngineError.RepayMoreThanBorrowed());
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            (RiskEngineError.Error err,, uint256 shortfall) =
                getAccountLiquidityInternal(borrower);
            if (err != RiskEngineError.Error.NO_ERROR) {
                return err;
            }

            if (shortfall == 0) {
                return RiskEngineError.Error.INSUFFICIENT_SHORTFALL;
            }

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint256 maxClose = $.closeFactorMantissa[pTokenBorrowed].toExp()
                .mul_ScalarTruncate(borrowBalance);
            if (repayAmount > maxClose) {
                return RiskEngineError.Error.TOO_MUCH_REPAY;
            }
        }
        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function seizeAllowed(address pTokenCollateral, address pTokenBorrowed)
        external
        view
        returns (RiskEngineError.Error)
    {
        RiskEngineData storage $ = _getRiskEngineStorage();

        // Pausing is a very serious situation - we revert to sound the alarms
        require(!$.seizeGuardianPaused, RiskEngineError.SeizePaused());

        if (!$.markets[pTokenCollateral].isListed || !$.markets[pTokenBorrowed].isListed)
        {
            return RiskEngineError.Error.MARKET_NOT_LISTED;
        }

        if (
            IPToken(pTokenCollateral).riskEngine() != IPToken(pTokenBorrowed).riskEngine()
        ) {
            return RiskEngineError.Error.RISKENGINE_MISMATCH;
        }

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function transferAllowed(address pToken, address src, uint256 transferTokens)
        external
        view
        returns (RiskEngineError.Error)
    {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(
            !_getRiskEngineStorage().transferGuardianPaused,
            RiskEngineError.TransferPaused()
        );

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        RiskEngineError.Error allowed = redeemAllowedInternal(pToken, src, transferTokens);
        if (allowed != RiskEngineError.Error.NO_ERROR) {
            return allowed;
        }

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function maxWithdraw(address pToken, address account)
        external
        view
        returns (uint256)
    {
        RiskEngineData storage $ = _getRiskEngineStorage();

        if (!$.markets[pToken].isListed) {
            return 0;
        }

        uint256 underlyingBalance = IPToken(pToken).balanceOfUnderlying(account);

        // Get the normalized price of the asset
        uint256 oraclePriceMantissa =
            IOracleEngine($.oracle).getUnderlyingPrice(IPToken(pToken));

        ExponentialNoError.Exp oraclePrice = oraclePriceMantissa.toExp();

        (RiskEngineError.Error err, uint256 withdrawLiquidity) =
            getWithdrawLiquidityInternal(account, _getCollateralFactor);
        if (err != RiskEngineError.Error.NO_ERROR) {
            return 0;
        }

        if (
            !$.markets[pToken].collateralMembership[account]
                || underlyingBalance.mul_(oraclePrice) < withdrawLiquidity
        ) {
            return underlyingBalance;
        } else {
            return withdrawLiquidity.div_(oraclePrice);
        }
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getAssetsIn(address account) external view returns (IPToken[] memory) {
        IPToken[] memory assetsIn = _getRiskEngineStorage().accountAssets[account];

        return assetsIn;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function checkCollateralMembership(address account, IPToken pToken)
        external
        view
        returns (bool)
    {
        return
            _getRiskEngineStorage().markets[address(pToken)].collateralMembership[account];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function checkBorrowMembership(address account, IPToken pToken)
        external
        view
        returns (bool)
    {
        return _getRiskEngineStorage().markets[address(pToken)].borrowMembership[account];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function accountCategory(address account) external view returns (uint8) {
        return _getRiskEngineStorage().accountCategory[account];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getAccountLiquidity(address account)
        external
        view
        returns (RiskEngineError.Error, uint256, uint256)
    {
        (RiskEngineError.Error err, uint256 liquidity, uint256 shortfall) =
            getAccountLiquidityInternal(account);

        return (err, liquidity, shortfall);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getAccountBorrowLiquidity(address account)
        external
        view
        returns (RiskEngineError.Error, uint256, uint256)
    {
        (RiskEngineError.Error err, uint256 liquidity, uint256 shortfall) =
        getHypotheticalAccountLiquidityInternal(
            account,
            IPToken(address(0)),
            _getRiskEngineStorage().accountCategory[account],
            0,
            0,
            _getCollateralFactor
        );

        return (err, liquidity, shortfall);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address pTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (RiskEngineError.Error, uint256, uint256) {
        (RiskEngineError.Error err, uint256 liquidity, uint256 shortfall) =
        getHypotheticalAccountLiquidityInternal(
            account,
            IPToken(pTokenModify),
            _getRiskEngineStorage().accountCategory[account],
            redeemTokens,
            borrowAmount,
            _getCollateralFactor
        );
        return (err, liquidity, shortfall);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function liquidateCalculateSeizeTokens(
        address borrower,
        address pTokenBorrowed,
        address pTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (RiskEngineError.Error, uint256) {
        address oracleEngine = _getRiskEngineStorage().oracle;

        /* Read oracle prices for borrowed and collateral markets */
        uint256 priceBorrowedMantissa =
            IOracleEngine(oracleEngine).getUnderlyingPrice(IPToken(pTokenBorrowed));
        uint256 priceCollateralMantissa =
            IOracleEngine(oracleEngine).getUnderlyingPrice(IPToken(pTokenCollateral));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (RiskEngineError.Error.PRICE_ERROR, 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint8 emodeCategory = _getRiskEngineStorage().accountCategory[borrower];
        uint256 exchangeRateMantissa = IPToken(pTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint256 seizeTokens;
        uint256 liquidationIncentiveMantissa;
        ExponentialNoError.Exp numerator;
        ExponentialNoError.Exp denominator;
        ExponentialNoError.Exp ratio;

        if (emodeCategory == 0) {
            liquidationIncentiveMantissa = _getRiskEngineStorage().markets[pTokenCollateral]
                .baseConfiguration
                .liquidationIncentiveMantissa;
        } else {
            liquidationIncentiveMantissa = _getRiskEngineStorage().emodes[emodeCategory]
                .baseConfiguration
                .liquidationIncentiveMantissa;
        }
        numerator =
            liquidationIncentiveMantissa.toExp().mul_(priceBorrowedMantissa.toExp());

        denominator = priceCollateralMantissa.toExp().mul_(exchangeRateMantissa.toExp());

        ratio = numerator.div_(denominator);

        seizeTokens = ratio.mul_ScalarTruncate(actualRepayAmount);

        return (RiskEngineError.Error.NO_ERROR, seizeTokens);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getAllMarkets() external view returns (IPToken[] memory) {
        return _getRiskEngineStorage().allMarkets[0];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function delegateAllowed(address user, address delegate)
        external
        view
        returns (bool)
    {
        return _getRiskEngineStorage().approvedDelegates[user][delegate];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function oracle() external view returns (address) {
        return _getRiskEngineStorage().oracle;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function collateralFactor(uint8 categoryId, IPToken pToken)
        external
        view
        returns (uint256)
    {
        return ExponentialNoError.Exp.unwrap(_getCollateralFactor(pToken, categoryId));
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getReserveShares()
        external
        view
        returns (uint256 ownerShareMantissa, uint256 configuratorShareMantissa)
    {
        ownerShareMantissa = _getRiskEngineStorage().ownerShareMantissa;
        configuratorShareMantissa = _getRiskEngineStorage().configuratorShareMantissa;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function liquidationThreshold(uint8 categoryId, IPToken pToken)
        external
        view
        returns (uint256)
    {
        return ExponentialNoError.Exp.unwrap(_getLiquidationThreshold(pToken, categoryId));
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function liquidationIncentive(uint8 categoryId, address pToken)
        external
        view
        returns (uint256)
    {
        if (categoryId == 0) {
            return _getRiskEngineStorage().markets[pToken]
                .baseConfiguration
                .liquidationIncentiveMantissa;
        } else {
            return _getRiskEngineStorage().emodes[categoryId]
                .baseConfiguration
                .liquidationIncentiveMantissa;
        }
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function closeFactor(address pToken) external view returns (uint256) {
        return _getRiskEngineStorage().closeFactorMantissa[pToken];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function supplyCap(address pToken) external view returns (uint256) {
        return _getRiskEngineStorage().supplyCaps[pToken];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function borrowCap(address pToken) external view returns (uint256) {
        return _getRiskEngineStorage().borrowCaps[pToken];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function emodeMarkets(uint8 categoryId)
        external
        view
        returns (address[] memory collateralTokens, address[] memory borrowTokens)
    {
        RiskEngineData storage $ = _getRiskEngineStorage();
        uint256 totalMarkets = $.allMarkets[0].length;

        address[] memory tempCollateral = new address[](totalMarkets);
        address[] memory tempBorrow = new address[](totalMarkets);
        uint256 collateralCount = 0;
        uint256 borrowCount = 0;

        address pToken;
        for (uint256 i = 0; i < totalMarkets; i++) {
            pToken = address($.allMarkets[0][i]);

            // Check collateral category
            if ($.collateralCategory[categoryId][pToken]) {
                tempCollateral[collateralCount++] = pToken;
            }

            // Check borrow category
            if ($.borrowCategory[categoryId][pToken]) {
                tempBorrow[borrowCount++] = pToken;
            }
        }

        collateralTokens = new address[](collateralCount);
        borrowTokens = new address[](borrowCount);

        for (uint256 i = 0; i < collateralCount; i++) {
            collateralTokens[i] = tempCollateral[i];
        }
        for (uint256 i = 0; i < borrowCount; i++) {
            borrowTokens[i] = tempBorrow[i];
        }
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function isDeprecated(IPToken pToken) public view returns (bool) {
        return _getRiskEngineStorage().markets[address(pToken)]
            .baseConfiguration
            .collateralFactorMantissa == 0
            && _getRiskEngineStorage().borrowGuardianPaused[address(pToken)] == true
            && pToken.reserveFactorMantissa() == 1e18;
    }

    /**
     * @notice Add the market to the market's "assets"
     * @param pToken The market address to add
     */
    function _addMarketInternal(address pToken) internal {
        RiskEngineData storage $ = _getRiskEngineStorage();

        for (uint256 i = 0; i < $.allMarkets[0].length; i++) {
            require(
                $.allMarkets[0][i] != IPToken(pToken), RiskEngineError.AlreadyListed()
            );
        }
        $.allMarkets[0].push(IPToken(pToken));
    }

    /**
     * @notice Add the market to the supplier's "assets in" for liquidity calculations
     * @param pToken The market to enter
     * @param supplier The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketCollateralInternal(IPToken pToken, address supplier)
        internal
        returns (RiskEngineError.Error)
    {
        RiskEngineData storage $ = _getRiskEngineStorage();
        Market storage marketToJoin = $.markets[address(pToken)];

        uint8 category = $.accountCategory[supplier];
        if (category != 0) {
            if (
                !$.collateralCategory[category][address(pToken)]
                    || !$.emodes[category].allowed
            ) {
                // should not allowed to enter market if market not supported in emode
                return RiskEngineError.Error.NOT_ALLOWED_AS_COLLATERAL;
            }
        }
        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return RiskEngineError.Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.collateralMembership[supplier] == true) {
            // already joined
            return RiskEngineError.Error.NO_ERROR;
        }

        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market as collateral
        marketToJoin.collateralMembership[supplier] = true;
        // skip if already added to assets as borrow
        if (!marketToJoin.borrowMembership[supplier]) {
            $.accountAssets[supplier].push(pToken);
        }

        emit MarketEntered(pToken, supplier);

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param pToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketBorrowInternal(IPToken pToken, address borrower)
        internal
        returns (RiskEngineError.Error)
    {
        Market storage marketToJoin = _getRiskEngineStorage().markets[address(pToken)];

        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market as borrow
        marketToJoin.borrowMembership[borrower] = true;
        // skip if already added to assets as collateral
        if (!marketToJoin.collateralMembership[borrower]) {
            _getRiskEngineStorage().accountAssets[borrower].push(pToken);
        }

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @notice Determine the current account liquidity with respect to collateral requirements
     * @return (possible error code,
     *             account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account)
        internal
        view
        returns (RiskEngineError.Error, uint256, uint256)
    {
        return getHypotheticalAccountLiquidityInternal(
            account,
            IPToken(address(0)),
            _getRiskEngineStorage().accountCategory[account],
            0,
            0,
            _getLiquidationThreshold
        );
    }

    /**
     * @notice Internal function to check if redeem is allowed for the redeemer
     */
    function redeemAllowedInternal(address pToken, address redeemer, uint256 redeemTokens)
        internal
        view
        returns (RiskEngineError.Error)
    {
        RiskEngineData storage $ = _getRiskEngineStorage();

        if (!$.markets[pToken].isListed) {
            return RiskEngineError.Error.MARKET_NOT_LISTED;
        }
        uint8 category = $.accountCategory[redeemer];
        // Should check if account is in emode and pToken is allowed
        if (category != 0 && !$.emodes[category].allowed) {
            return RiskEngineError.Error.EMODE_NOT_ALLOWED;
        }

        /* If the redeemer is not 'in' the market as collateral, then we can bypass the liquidity check */
        if (!$.markets[pToken].collateralMembership[redeemer]) {
            return RiskEngineError.Error.NO_ERROR;
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (RiskEngineError.Error err,, uint256 shortfall) =
        getHypotheticalAccountLiquidityInternal(
            redeemer,
            IPToken(pToken),
            $.accountCategory[redeemer],
            redeemTokens,
            0,
            _getCollateralFactor
        );
        if (err != RiskEngineError.Error.NO_ERROR) {
            return err;
        }
        if (shortfall > 0) {
            return RiskEngineError.Error.INSUFFICIENT_LIQUIDITY;
        }

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param pTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral pToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
     *             hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        IPToken pTokenModify,
        uint8 categoryId,
        uint256 redeemTokens,
        uint256 borrowAmount,
        function (IPToken,uint8) internal view returns (ExponentialNoError.Exp) threshold
    ) internal view returns (RiskEngineError.Error, uint256, uint256) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        vars.oracle = IOracleEngine(_getRiskEngineStorage().oracle);

        // For each asset the account is in
        IPToken[] memory accountAssets = _getRiskEngineStorage().accountAssets[account];
        for (uint256 i = 0; i < accountAssets.length; i++) {
            IPToken asset = accountAssets[i];

            // Read the balances and exchange rate from the pToken
            (vars.pTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) =
                asset.getAccountSnapshot(account);

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = vars.oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (RiskEngineError.Error.PRICE_ERROR, 0, 0);
            }

            vars.oraclePrice = vars.oraclePriceMantissa.toExp();

            vars.threshold = threshold(asset, categoryId);
            vars.exchangeRate = vars.exchangeRateMantissa.toExp();

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenom =
                vars.oraclePrice.mul_(vars.threshold.mul_(vars.exchangeRate));

            if (
                _getRiskEngineStorage().markets[address(asset)].collateralMembership[account]
            ) {
                // sumCollateral += tokensToDenom * pTokenBalance
                vars.sumCollateral = vars.tokensToDenom.mul_ScalarTruncateAddUInt(
                    vars.pTokenBalance, vars.sumCollateral
                );
            }
            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = vars.oraclePrice.mul_ScalarTruncateAddUInt(
                vars.borrowBalance, vars.sumBorrowPlusEffects
            );
            // Calculate effects of interacting with pTokenModify
            if (asset == pTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = vars.tokensToDenom.mul_ScalarTruncateAddUInt(
                    redeemTokens, vars.sumBorrowPlusEffects
                );

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = vars.oraclePrice.mul_ScalarTruncateAddUInt(
                    borrowAmount, vars.sumBorrowPlusEffects
                );
            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (
                RiskEngineError.Error.NO_ERROR,
                vars.sumCollateral - vars.sumBorrowPlusEffects,
                0
            );
        } else {
            return (
                RiskEngineError.Error.NO_ERROR,
                0,
                vars.sumBorrowPlusEffects - vars.sumCollateral
            );
        }
    }

    /**
     * @notice Calculates the available withdrawal liquidity for an account,
     * factoring in thresholds and collateral.
     * @dev Returns liquidity in underlying asset terms,
     * or zero if insufficient liquidity or price error occurs.
     * @param account The account to check.
     * @param threshold The threshold factor function for liquidity calculation.
     * @return Error code and maximum withdrawable amount.
     */
    function getWithdrawLiquidityInternal(
        address account,
        function (IPToken,uint8) internal view returns (ExponentialNoError.Exp) threshold
    ) internal view returns (RiskEngineError.Error, uint256) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        vars.oracle = IOracleEngine(_getRiskEngineStorage().oracle);
        vars.accountCategory = _getRiskEngineStorage().accountCategory[account];

        // For each asset the account is in
        IPToken[] memory assets = _getRiskEngineStorage().accountAssets[account];
        for (uint256 i = 0; i < assets.length; i++) {
            IPToken asset = assets[i];

            // Read the balances and exchange rate from the pToken
            (vars.pTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) =
                asset.getAccountSnapshot(account);

            vars.threshold = threshold(asset, vars.accountCategory);
            vars.exchangeRate = vars.exchangeRateMantissa.toExp();

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = vars.oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (RiskEngineError.Error.PRICE_ERROR, 0);
            }

            vars.oraclePrice = vars.oraclePriceMantissa.toExp();

            // Pre-compute a conversion factor from tokens -> ether (normalized price value) w/o threshold
            vars.tokensToDenom = vars.oraclePrice.mul_(vars.exchangeRate);

            if (
                _getRiskEngineStorage().markets[address(asset)].collateralMembership[account]
            ) {
                // sumLiquidity += tokensToDenom * pTokenBalance
                vars.sumLiquidity = vars.tokensToDenom.mul_ScalarTruncateAddUInt(
                    vars.pTokenBalance, vars.sumLiquidity
                );

                // sumCollateral += tokensToDenom * threshold * pTokenBalance
                vars.sumCollateral = (vars.tokensToDenom.mul_(vars.threshold))
                    .mul_ScalarTruncateAddUInt(vars.pTokenBalance, vars.sumCollateral);
            }

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = vars.oraclePrice.mul_ScalarTruncateAddUInt(
                vars.borrowBalance, vars.sumBorrowPlusEffects
            );
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            uint256 excessCollateral = vars.sumCollateral - vars.sumBorrowPlusEffects;
            return (
                RiskEngineError.Error.NO_ERROR,
                excessCollateral * vars.sumLiquidity / vars.sumCollateral
            );
        } else {
            return (RiskEngineError.Error.INSUFFICIENT_LIQUIDITY, 0);
        }
    }

    /**
     * @dev Return collateral factor for a market
     * @param asset Address for asset
     * @return Collateral factor as exponential
     */
    function _getCollateralFactor(IPToken asset, uint8 emodeCategory)
        internal
        view
        returns (ExponentialNoError.Exp)
    {
        RiskEngineData storage $ = _getRiskEngineStorage();

        // Check if asset is in emode category and category is not 0
        bool useEmode =
            emodeCategory != 0 && $.collateralCategory[emodeCategory][address(asset)];

        return (
            useEmode
                ? $.emodes[emodeCategory].baseConfiguration.collateralFactorMantissa
                : $.markets[address(asset)].baseConfiguration.collateralFactorMantissa
        ).toExp();
    }

    /**
     * @dev Retrieves liquidation threshold for a market as an exponential
     * @param asset Address for asset to liquidation threshold
     * @return Liquidation threshold as exponential
     */
    function _getLiquidationThreshold(IPToken asset, uint8 emodeCategory)
        internal
        view
        returns (ExponentialNoError.Exp)
    {
        RiskEngineData storage $ = _getRiskEngineStorage();

        // Check if asset is in emode category and category is not 0
        bool useEmode =
            emodeCategory != 0 && $.collateralCategory[emodeCategory][address(asset)];

        return (
            useEmode
                ? $.emodes[emodeCategory].baseConfiguration.liquidationThresholdMantissa
                : $.markets[address(asset)].baseConfiguration.liquidationThresholdMantissa
        ).toExp();
    }
}
