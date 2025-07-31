//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    SafeERC20, IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {ExponentialNoError} from "@utils/ExponentialNoError.sol";
import {PTokenStorage} from "@storage/PTokenStorage.sol";
import {IRiskEngine, RiskEngineError} from "@interfaces/IRiskEngine.sol";
import {IRBAC} from "@interfaces/IRBAC.sol";
import {RBACStorage} from "@storage/RBACStorage.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";
import {CommonError} from "@errors/CommonError.sol";
import {PTokenError} from "@errors/PTokenError.sol";
import {IPToken} from "@interfaces/IPToken.sol";

/**
 * @title Pike Markets PToken Contract
 * @notice ERC20 Compatible PTokens
 * @author NUTS Finance (hello@pike.finance)
 */
contract PTokenModule is IPToken, PTokenStorage, OwnableMixin, RBACStorage {
    using ExponentialNoError for ExponentialNoError.Exp;
    using ExponentialNoError for uint256;
    using SafeERC20 for IERC20;

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        require(!_reentrancyGuardEntered(), CommonError.ReentrancyGuardReentrantCall());

        assembly ("memory-safe") {
            tstore(_SLOT_PTOKEN_TRANSIENT_STORAGE, 1)
        }
        _;
        assembly ("memory-safe") {
            tstore(_SLOT_PTOKEN_TRANSIENT_STORAGE, 0)
        }
    }

    /**
     * @notice Initialize the pike market
     * @param underlying_ The address of the underlying token
     * @param riskEngine_ The address of the RiskEngine
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param reserveFactorMantissa_ percentage of borrow interests that goes to protocol, scaled by 1e18
     * @param protocolSeizeShareMantissa_ The share of seized collateral that goes to protocol reserves, scaled by 1e18
     * @param borrowRateMaxMantissa_ The maximum borrow interest rate for the market, scaled by 1e18
     * @param name_ ERC20 name of this token
     * @param symbol_ ERC20 symbol of this token
     * @param decimals_ ERC20 decimal precision of this token
     */
    function initialize(
        address underlying_,
        IRiskEngine riskEngine_,
        uint256 initialExchangeRateMantissa_,
        uint256 reserveFactorMantissa_,
        uint256 protocolSeizeShareMantissa_,
        uint256 borrowRateMaxMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external onlyOwner {
        PTokenData storage $ = _getPTokenStorage();
        require(
            $.accrualBlockTimestamp == 0 && $.borrowIndex == 0,
            CommonError.AlreadyInitialized()
        );
        require(
            initialExchangeRateMantissa_ != 0 && borrowRateMaxMantissa_ != 0,
            CommonError.ZeroValue()
        );
        require(
            underlying_ != address(0) && address(riskEngine_) != address(0),
            CommonError.ZeroAddress()
        );

        // Set initial exchange rate
        $.initialExchangeRateMantissa = initialExchangeRateMantissa_;

        _setProtocolSeizeShareMantissa(protocolSeizeShareMantissa_);

        $.borrowRateMaxMantissa = borrowRateMaxMantissa_;

        // set risk engine
        _setRiskEngine(riskEngine_);

        // Initialize block timestamp and borrow index (block timestamp is set to current block timestamp)
        $.accrualBlockTimestamp = _getBlockTimestamp();
        $.borrowIndex = _MANTISSA_ONE;

        _setReserveFactorFresh(reserveFactorMantissa_);

        $.name = name_;
        $.symbol = symbol_;
        $.decimals = decimals_;

        // Set underlying and sanity check it
        $.underlying = underlying_;
        IERC20(underlying_).totalSupply();
    }

    /**
     * @inheritdoc IPToken
     */
    function setBorrowRateMax(uint256 newBorrowRateMaxMantissa) external {
        _checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);

        PTokenData storage $ = _getPTokenStorage();

        uint256 oldBorrowRateMaxMantissa = $.borrowRateMaxMantissa;
        $.borrowRateMaxMantissa = newBorrowRateMaxMantissa;

        emit NewBorrowRateMax(oldBorrowRateMaxMantissa, newBorrowRateMaxMantissa);
    }

    /**
     * @inheritdoc IPToken
     */
    function setReserveFactor(uint256 newReserveFactorMantissa) external {
        _checkPermission(_RESERVE_MANAGER_PERMISSION, msg.sender);
        accrueInterest();
        // _setReserveFactorFresh emits reserve-factor-specific logs on errors, so we don't need to.
        _setReserveFactorFresh(newReserveFactorMantissa);
    }

    /**
     * @inheritdoc IPToken
     */
    function setProtocolSeizeShare(uint256 newProtocolSeizeShareMantissa) external {
        _checkPermission(_RESERVE_MANAGER_PERMISSION, msg.sender);

        _setProtocolSeizeShareMantissa(newProtocolSeizeShareMantissa);
    }

    /**
     * @inheritdoc IPToken
     */
    function addReserves(uint256 addAmount) external nonReentrant {
        accrueInterest();

        // _addReservesFresh emits reserve-addition-specific logs on errors, so we don't need to.
        _addReservesFresh(addAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function reduceReservesEmergency(uint256 reduceAmount) external nonReentrant {
        _checkPermission(_EMERGENCY_WITHDRAWER_PERMISSION, msg.sender);
        PTokenData storage $ = _getPTokenStorage();
        // _reduceReserves emits reserve-reduction-specific logs on errors, so we don't need to.

        // store new reserve
        $.totalReserves = _reduceReserves(reduceAmount, $.totalReserves);
        emit EmergencyWithdrawn(msg.sender, reduceAmount, $.totalReserves);
    }

    /**
     * @inheritdoc IPToken
     */
    function reduceReservesOwner(uint256 reduceAmount) external nonReentrant {
        _checkPermission(_OWNER_WITHDRAWER_PERMISSION, msg.sender);
        PTokenData storage $ = _getPTokenStorage();
        // _reduceReserves emits reserve-reduction-specific logs on errors, so we don't need to.

        // store new reserve
        $.ownerReserves = _reduceReserves(reduceAmount, $.ownerReserves);
        $.totalReserves -= reduceAmount;
        emit ReservesReduced(msg.sender, reduceAmount, $.ownerReserves);
    }

    /**
     * @inheritdoc IPToken
     */
    function reduceReservesConfigurator(uint256 reduceAmount) external nonReentrant {
        _checkPermission(_RESERVE_WITHDRAWER_PERMISSION, msg.sender);
        PTokenData storage $ = _getPTokenStorage();
        // _reduceReserves emits reserve-reduction-specific logs on errors, so we don't need to.

        // store new reserve
        $.configuratorReserves = _reduceReserves(reduceAmount, $.configuratorReserves);
        $.totalReserves -= reduceAmount;
        emit ReservesReduced(msg.sender, reduceAmount, $.configuratorReserves);
    }

    /**
     * @inheritdoc IPToken
     */
    function sweepToken(IERC20 token) external {
        _checkPermission(_RESERVE_WITHDRAWER_PERMISSION, msg.sender);
        require(
            address(token) != _getPTokenStorage().underlying,
            PTokenError.SweepNotAllowed()
        );
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, balance);
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return True if the transfer succeeded, reverts otherwise
     */
    function transfer(address dst, uint256 amount)
        external
        override
        nonReentrant
        returns (bool)
    {
        _transferTokens(msg.sender, msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return True if the transfer succeeded, reverts otherwise
     */
    function transferFrom(address src, address dst, uint256 amount)
        external
        override
        nonReentrant
        returns (bool)
    {
        _transferTokens(msg.sender, src, dst, amount);
        return true;
    }

    /**
     * @inheritdoc IPToken
     */
    function mint(uint256 tokenAmount, address receiver)
        external
        nonReentrant
        returns (uint256)
    {
        require(receiver != address(0), CommonError.ZeroAddress());
        accrueInterest();
        (, uint256 assets) = mintFresh(msg.sender, receiver, tokenAmount, 0);
        return assets;
    }

    /**
     * @inheritdoc IPToken
     */
    function deposit(uint256 mintAmount, address receiver)
        external
        nonReentrant
        returns (uint256)
    {
        require(receiver != address(0), CommonError.ZeroAddress());

        accrueInterest();
        (uint256 shares,) = mintFresh(msg.sender, receiver, 0, mintAmount);
        return shares;
    }

    /**
     * @inheritdoc IPToken
     */
    function redeem(uint256 redeemTokens, address receiver, address owner)
        external
        nonReentrant
        returns (uint256)
    {
        accrueInterest();

        (, uint256 assets) = redeemFresh(receiver, owner, redeemTokens, 0);
        return assets;
    }

    /**
     * @inheritdoc IPToken
     */
    function withdraw(uint256 redeemAmount, address receiver, address owner)
        external
        nonReentrant
        returns (uint256)
    {
        accrueInterest();
        (uint256 shares,) = redeemFresh(receiver, owner, 0, redeemAmount);
        return shares;
    }

    /**
     * @inheritdoc IPToken
     */
    function borrow(uint256 borrowAmount) external nonReentrant {
        accrueInterest();

        borrowFresh(msg.sender, msg.sender, borrowAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowOnBehalfOf(address onBehalfOf, uint256 borrowAmount)
        external
        nonReentrant
    {
        _isDelegateeOf(onBehalfOf);
        accrueInterest();

        borrowFresh(msg.sender, onBehalfOf, borrowAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function repayBorrow(uint256 repayAmount) external nonReentrant {
        accrueInterest();

        repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function repayBorrowOnBehalfOf(address onBehalfOf, uint256 repayAmount)
        external
        nonReentrant
    {
        accrueInterest();

        repayBorrowFresh(msg.sender, onBehalfOf, repayAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        IPToken pTokenCollateral
    ) external nonReentrant {
        accrueInterest();

        (bool success,) =
            address(pTokenCollateral).call(abi.encodeWithSignature("accrueInterest()"));

        // accrueInterest emits logs on errors, but we want to log the fact that an attempted liquidation failed
        require(success, PTokenError.LiquidateAccrueCollateralInterestFailed());

        // liquidateBorrowFresh emits borrow-specific logs on errors, so we don't need to
        liquidateBorrowFresh(msg.sender, borrower, repayAmount, pTokenCollateral);
    }

    /**
     * @inheritdoc IPToken
     */
    function seize(address liquidator, address borrower, uint256 seizeTokens)
        external
        nonReentrant
    {
        seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (type(uint256).max for infinite)
     * @return success Whether or not the approval succeeded
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        require(spender != address(0), CommonError.ZeroAddress());

        address src = msg.sender;
        _getPTokenStorage().transferAllowances[src][spender] = amount;
        emit Approval(src, spender, amount);
        return true;
    }

    /**
     * @notice Get the current allowance from `owner` for `spender`
     * @param owner The address of the account which owns the tokens to be spent
     * @param spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (type(uint256).max for infinite)
     */
    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _getPTokenStorage().transferAllowances[owner][spender];
    }

    /**
     * @inheritdoc IPToken
     */
    function convertToShares(uint256 assets) external view returns (uint256) {
        uint256 _totalSupply = _getPTokenStorage().totalSupply;
        if (_totalSupply == 0) {
            return assets;
        } else {
            return assets * _totalSupply / totalAssets();
        }
    }

    /**
     * @inheritdoc IPToken
     */
    function convertToAssets(uint256 shares) external view returns (uint256) {
        uint256 _totalSupply = _getPTokenStorage().totalSupply;
        if (_totalSupply == 0) {
            return shares;
        } else {
            return shares * totalAssets() / _totalSupply;
        }
    }

    /**
     * @inheritdoc IPToken
     */
    function maxMint(address receiver) external view returns (uint256) {
        return maxDeposit(receiver).div_(exchangeRateCurrent().toExp());
    }

    /**
     * @inheritdoc IPToken
     */
    function maxWithdraw(address owner) external view returns (uint256) {
        return _getPTokenStorage().riskEngine.maxWithdraw(address(this), owner);
    }

    /**
     * @inheritdoc IPToken
     */
    function maxRedeem(address owner) external view returns (uint256 maxShares) {
        return _getPTokenStorage().riskEngine.maxWithdraw(address(this), owner).div_(
            exchangeRateCurrent().toExp()
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = assets.div_(exchangeRateCurrent().toExp());
    }

    /**
     * @inheritdoc IPToken
     */
    function previewMint(uint256 shares) external view returns (uint256 assets) {
        assets = shares.mul_(exchangeRateCurrent().toExp());
    }

    /**
     * @inheritdoc IPToken
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        assets = exchangeRateCurrent().toExp().mul_ScalarTruncate(shares);
    }

    /**
     * @inheritdoc IPToken
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares) {
        ExponentialNoError.Exp exchangeRate = exchangeRateCurrent().toExp();

        shares = assets.div_(exchangeRate);
        uint256 _redeemAmount = shares.mul_(exchangeRate);
        if (_redeemAmount != 0 && _redeemAmount != assets) shares++;
    }

    /**
     * @notice Get the token balance of the `owner`
     * @param owner The address of the account to query
     * @return The number of tokens owned by `owner`
     */
    function balanceOf(address owner) external view override returns (uint256) {
        return _getPTokenStorage().accountTokens[owner];
    }

    /**
     * @inheritdoc IPToken
     */
    function accrualBlockTimestamp() external view returns (uint256) {
        return _getPTokenStorage().accrualBlockTimestamp;
    }

    /**
     * @inheritdoc IPToken
     */
    function riskEngine() external view returns (IRiskEngine) {
        return _getPTokenStorage().riskEngine;
    }

    /**
     * @inheritdoc IPToken
     */
    function reserveFactorMantissa() external view returns (uint256) {
        return _getPTokenStorage().reserveFactorMantissa;
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowRateMaxMantissa() external view returns (uint256) {
        return _getPTokenStorage().borrowRateMaxMantissa;
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowIndex() external view returns (uint256) {
        return _getPTokenStorage().borrowIndex;
    }

    /**
     * @inheritdoc IPToken
     */
    function totalBorrows() external view returns (uint256) {
        return _getPTokenStorage().totalBorrows;
    }

    /**
     * @inheritdoc IPToken
     */
    function ownerReserves() external view returns (uint256) {
        return _getPTokenStorage().ownerReserves;
    }

    /**
     * @inheritdoc IPToken
     */
    function configuratorReserves() external view returns (uint256) {
        return _getPTokenStorage().configuratorReserves;
    }

    /**
     * @inheritdoc IPToken
     */
    function totalReserves() external view returns (uint256) {
        return _getPTokenStorage().totalReserves;
    }

    /**
     * @inheritdoc IPToken
     */
    function totalSupply() external view returns (uint256) {
        return _getPTokenStorage().totalSupply;
    }

    /**
     * @inheritdoc IPToken
     */
    function name() external view returns (string memory) {
        return _getPTokenStorage().name;
    }

    /**
     * @inheritdoc IPToken
     */
    function symbol() external view returns (string memory) {
        return _getPTokenStorage().symbol;
    }

    /**
     * @inheritdoc IPToken
     */
    function decimals() external view returns (uint8) {
        return _getPTokenStorage().decimals;
    }

    /**
     * @inheritdoc IPToken
     */
    function balanceOfUnderlying(address owner) external view returns (uint256) {
        return exchangeRateCurrent().toExp().mul_ScalarTruncate(
            _getPTokenStorage().accountTokens[owner]
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function getAccountSnapshot(address account)
        external
        view
        returns (uint256, uint256, uint256)
    {
        return (
            _getPTokenStorage().accountTokens[account],
            borrowBalanceStoredInternal(account),
            exchangeRateStoredInternal()
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function exchangeRateStored() external view returns (uint256) {
        return exchangeRateStoredInternal();
    }

    /**
     * @inheritdoc IPToken
     */
    function initialExchangeRate() external view returns (uint256) {
        return _getPTokenStorage().initialExchangeRateMantissa;
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowBalanceStored(address account) external view returns (uint256) {
        return borrowBalanceStoredInternal(account);
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowRatePerSecond() external view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();

        return IInterestRateModel(address(this)).getBorrowRate(
            getCash(), snapshot.totalBorrow, snapshot.totalReserve
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function supplyRatePerSecond() external view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();

        return IInterestRateModel(address(this)).getSupplyRate(
            getCash(),
            snapshot.totalBorrow,
            snapshot.totalReserve,
            _getPTokenStorage().reserveFactorMantissa
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function totalBorrowsCurrent() external view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();
        return snapshot.totalBorrow;
    }

    /**
     * @inheritdoc IPToken
     */
    function totalReservesCurrent() external view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();
        return snapshot.totalReserve;
    }

    /**
     * @inheritdoc IPToken
     */
    function ownerReservesCurrent() external view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();
        return snapshot.ownerReserve;
    }

    /**
     * @inheritdoc IPToken
     */
    function configuratorReservesCurrent() external view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();
        return snapshot.configuratorReserve;
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowBalanceCurrent(address account) external view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();
        BorrowSnapshot memory borrowSnapshot = _getPTokenStorage().accountBorrows[account];

        if (borrowSnapshot.principal == 0) return 0;

        return borrowSnapshot.principal * snapshot.accBorrowIndex
            / borrowSnapshot.interestIndex;
    }

    /**
     * @inheritdoc IPToken
     */
    function asset() external view returns (address) {
        return _getPTokenStorage().underlying;
    }

    /**
     * @inheritdoc IPToken
     */
    function protocolSeizeShareMantissa() external view returns (uint256) {
        return _getPTokenStorage().protocolSeizeShareMantissa;
    }

    /**
     * @inheritdoc IPToken
     */
    function accrueInterest() public {
        /* Remember the initial block timestamp */
        uint256 currentBlockTimestamp = _getBlockTimestamp();
        PTokenData storage $ = _getPTokenStorage();

        /* Short-circuit accumulating 0 interest */
        if ($.accrualBlockTimestamp == currentBlockTimestamp) {
            return;
        }

        /// Get accrued snapshot
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();

        /// return without updating accrual timestamp to revert with freshnesscheck
        if (
            IInterestRateModel(address(this)).getBorrowRate(
                getCash(), snapshot.totalBorrow, snapshot.totalReserve
            ) > $.borrowRateMaxMantissa
        ) {
            return;
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        $.accrualBlockTimestamp = currentBlockTimestamp;
        $.borrowIndex = snapshot.accBorrowIndex;
        $.totalBorrows = snapshot.totalBorrow;
        $.totalReserves = snapshot.totalReserve;
        $.ownerReserves = snapshot.ownerReserve;
        $.configuratorReserves = snapshot.configuratorReserve;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(
            getCash(),
            snapshot.totalReserve,
            snapshot.accBorrowIndex,
            snapshot.totalBorrow
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function totalAssets() public view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();
        return (getCash() + snapshot.totalBorrow - snapshot.totalReserve);
    }

    /**
     * @inheritdoc IPToken
     */
    function maxDeposit(address account) public view returns (uint256) {
        RiskEngineError.Error allowed =
            _getPTokenStorage().riskEngine.mintAllowed(account, address(this), 1);
        if (allowed != RiskEngineError.Error.NO_ERROR) {
            return 0;
        }
        uint256 cap = _getPTokenStorage().riskEngine.supplyCap(address(this));
        if (cap != type(uint256).max) {
            return cap - totalAssets();
        }
        return cap;
    }

    /**
     * @inheritdoc IPToken
     */
    function exchangeRateCurrent() public view returns (uint256) {
        uint256 _totalSupply = _getPTokenStorage().totalSupply;

        if (_totalSupply == 0) {
            return _getPTokenStorage().initialExchangeRateMantissa;
        }
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();

        return (getCash() + snapshot.totalBorrow - snapshot.totalReserve)
            * ExponentialNoError.expScale / _totalSupply;
    }

    /**
     * @inheritdoc IPToken
     */
    function getCash() public view returns (uint256) {
        return IERC20(_getPTokenStorage().underlying).balanceOf(address(this));
    }

    /**
     * @notice User supplies assets into the market and receives pTokens in exchange
     * @dev Assumes interest has already been accrued up to the current timestamp
     * @param minter The address of the account which is supplying the assets
     * @param onBehalfOf The address whom the supply will be attributed to
     * @param mintTokensIn The amount of ptoken to mint for supply
     * @param mintAmountIn The amount of the underlying asset to supply
     */
    function mintFresh(
        address minter,
        address onBehalfOf,
        uint256 mintTokensIn,
        uint256 mintAmountIn
    ) internal returns (uint256, uint256) {
        require(mintTokensIn == 0 || mintAmountIn == 0, PTokenError.OnlyOneInputAllowed());

        ExponentialNoError.Exp exchangeRate = exchangeRateStoredInternal().toExp();

        if (mintTokensIn > 0) {
            /* mintAmount = mintTokensIn x exchangeRateStored */
            mintAmountIn = mintTokensIn.mul_(exchangeRate);
        }

        PTokenData storage $ = _getPTokenStorage();

        /* Fail if mint not allowed */
        RiskEngineError.Error allowed =
            $.riskEngine.mintAllowed(minter, address(this), mintAmountIn);
        require(
            allowed == RiskEngineError.Error.NO_ERROR,
            PTokenError.MintRiskEngineRejection(uint256(allowed))
        );

        /* Verify market's block timestamp equals current block timestamp */
        require(
            $.accrualBlockTimestamp == _getBlockTimestamp(),
            PTokenError.MintFreshnessCheck()
        );

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         *  We call `doTransferIn` for the minter and the mintAmount.
         *  `doTransferIn` reverts if anything goes wrong, since we can't be sure if
         *  side-effects occurred. The function returns the amount actually transferred,
         *  in case of a fee. On success, the pToken holds an additional `actualMintAmount`
         *  of cash.
         */
        uint256 actualMintAmount = doTransferIn(minter, mintAmountIn);

        /*
         * We get the current exchange rate and calculate the number of pTokens to be minted:
         *  mintTokens = actualMintAmount / exchangeRate
         */

        uint256 mintTokens = actualMintAmount.div_(exchangeRate);

        /// mint dead shares if it's initial mint
        if ($.totalSupply == 0) {
            $.totalSupply = mintTokens;
            mintTokens = mintTokens - MINIMUM_DEAD_SHARES;
        } else {
            $.totalSupply = $.totalSupply + mintTokens;
        }

        require(mintTokens != 0, PTokenError.ZeroTokensMinted());

        if ($.accountTokens[onBehalfOf] == 0) {
            $.riskEngine.mintVerify(onBehalfOf);
        }

        /*
         * We calculate the new total supply of pTokens and onBehalfOf token balance, checking for overflow:
         *  totalSupplyNew = totalSupply + mintTokens
         *  accountTokensNew = accountTokens[onBehalfOf] + mintTokens
         * And write them into storage
         */
        $.accountTokens[onBehalfOf] = $.accountTokens[onBehalfOf] + mintTokens;

        /* We emit a Mint event, and a Transfer event */
        emit Deposit(minter, onBehalfOf, actualMintAmount, mintTokens);
        emit Transfer(address(0), onBehalfOf, mintTokens);
        return (mintTokens, actualMintAmount);
    }

    /**
     * @notice User redeems pTokens in exchange for the underlying asset
     * @dev Assumes interest has already been accrued up to the current timestamp
     * @param receiver The address of the account which receives the tokens
     * @param onBehalfOf The address of user on behalf of whom to redeem
     * @param redeemTokensIn The number of pTokens to redeem into underlying
     * (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     * @param redeemAmountIn The number of underlying tokens to receive from redeeming pTokens
     */
    function redeemFresh(
        address receiver,
        address onBehalfOf,
        uint256 redeemTokensIn,
        uint256 redeemAmountIn
    ) internal returns (uint256, uint256) {
        require(receiver != address(0), CommonError.ZeroAddress());

        require(
            redeemTokensIn == 0 || redeemAmountIn == 0, PTokenError.OnlyOneInputAllowed()
        );

        /* exchangeRate = invoke Exchange Rate Stored() */
        ExponentialNoError.Exp exchangeRate = exchangeRateStoredInternal().toExp();

        uint256 redeemTokens;
        /* If redeemTokensIn > 0: */
        if (redeemTokensIn > 0) {
            /*
             * We calculate the amount of ptoken to be redeemed:
             *  redeemTokens = redeemTokensIn
             */
            redeemTokens = redeemTokensIn;
        } else {
            /*
             * We get the current exchange rate and calculate the amount to be redeemed:
             *  redeemTokens = redeemAmountIn / exchangeRate
             */
            redeemTokens = redeemAmountIn.div_(exchangeRate);
            uint256 _redeemAmount = redeemTokens.mul_(exchangeRate);
            if (_redeemAmount != 0 && _redeemAmount != redeemAmountIn) redeemTokens++;
        }

        /* redeemAmount = redeemTokens x exchangeRateCurrent */
        uint256 redeemAmount = exchangeRate.mul_ScalarTruncate(redeemTokens);

        PTokenData storage $ = _getPTokenStorage();
        /* Fail if redeem not allowed */
        RiskEngineError.Error allowed =
            $.riskEngine.redeemAllowed(address(this), onBehalfOf, redeemTokens);
        require(
            allowed == RiskEngineError.Error.NO_ERROR,
            PTokenError.RedeemRiskEngineRejection(uint256(allowed))
        );

        /* Verify market's block timestamp equals current block timestamp */
        require(
            $.accrualBlockTimestamp == _getBlockTimestamp(),
            PTokenError.RedeemFreshnessCheck()
        );

        /* Fail gracefully if protocol has insufficient cash */
        require(getCash() >= redeemAmount, PTokenError.RedeemTransferOutNotPossible());

        if (msg.sender != onBehalfOf) {
            _spendAllowance(onBehalfOf, msg.sender, redeemTokens);
        }

        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We write the previously calculated values into storage.
         *  Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
         */
        $.totalSupply = $.totalSupply - redeemTokens;
        $.accountTokens[onBehalfOf] = $.accountTokens[onBehalfOf] - redeemTokens;

        /*
         * We invoke doTransferOut for the receiver and the redeemAmount.
         *  On success, the pToken has redeemAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        doTransferOut(receiver, redeemAmount);
        require(redeemTokens != 0 || redeemAmount == 0, PTokenError.InvalidRedeemTokens());
        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(onBehalfOf, address(0), redeemTokens);
        emit Withdraw(msg.sender, receiver, onBehalfOf, redeemAmount, redeemTokens);
        return (redeemTokens, redeemAmount);
    }

    /**
     * @notice Users borrow assets from the protocol to their own address
     * @param borrower The address of the account which is borrowing the tokens
     * @param onBehalfOf The address on behalf of whom to borrow
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrowFresh(address borrower, address onBehalfOf, uint256 borrowAmount)
        internal
    {
        PTokenData storage $ = _getPTokenStorage();
        /* Fail if borrow not allowed */
        RiskEngineError.Error allowed =
            $.riskEngine.borrowAllowed(address(this), onBehalfOf, borrowAmount);
        require(
            allowed == RiskEngineError.Error.NO_ERROR,
            PTokenError.BorrowRiskEngineRejection(uint256(allowed))
        );

        /* Verify market's block timestamp equals current block timestamp */
        require(
            $.accrualBlockTimestamp == _getBlockTimestamp(),
            PTokenError.BorrowFreshnessCheck()
        );

        /* Fail gracefully if protocol has insufficient underlying cash */
        require(getCash() >= borrowAmount, PTokenError.BorrowCashNotAvailable());

        /*
         * We calculate the new borrower and total borrow balances, failing on overflow:
         *  accountBorrowNew = accountBorrow + borrowAmount
         *  totalBorrowsNew = totalBorrows + borrowAmount
         */
        uint256 accountBorrowsPrev = borrowBalanceStoredInternal(onBehalfOf);
        uint256 accountBorrowsNew = accountBorrowsPrev + borrowAmount;
        uint256 totalBorrowsNew = $.totalBorrows + borrowAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We write the previously calculated values into storage.
         *  Note: Avoid token reentrancy attacks by writing increased borrow before external transfer.
        `*/
        $.accountBorrows[onBehalfOf].principal = accountBorrowsNew;
        $.accountBorrows[onBehalfOf].interestIndex = $.borrowIndex;
        $.totalBorrows = totalBorrowsNew;

        /*
         * We invoke doTransferOut for the borrower and the borrowAmount.
         *  On success, the pToken borrowAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        doTransferOut(borrower, borrowAmount);

        /* We emit a Borrow event */
        emit Borrow(
            borrower, onBehalfOf, borrowAmount, accountBorrowsNew, totalBorrowsNew
        );
    }

    /**
     * @notice Borrows are repaid by another user (possibly the borrower).
     * @param payer the account paying off the borrow
     * @param onBehalfOf the account with the debt being payed off
     * @param repayAmount the amount of underlying tokens being returned,
     * or type(uint256).max for the full outstanding amount
     * @return the actual repayment amount.
     */
    function repayBorrowFresh(address payer, address onBehalfOf, uint256 repayAmount)
        internal
        returns (uint256)
    {
        PTokenData storage $ = _getPTokenStorage();
        /* Fail if repayBorrow not allowed */
        RiskEngineError.Error allowed = $.riskEngine.repayBorrowAllowed(address(this));
        require(
            allowed == RiskEngineError.Error.NO_ERROR,
            PTokenError.RepayBorrowRiskEngineRejection(uint256(allowed))
        );

        /* Verify market's block timestamp equals current block timestamp */
        require(
            $.accrualBlockTimestamp == _getBlockTimestamp(),
            PTokenError.RepayBorrowFreshnessCheck()
        );

        /* We fetch the amount the borrower owes, with accumulated interest */
        uint256 accountBorrowsPrev = borrowBalanceStoredInternal(onBehalfOf);

        /* If repayAmount == type(uint256).max, repayAmount = accountBorrows */
        uint256 repayAmountFinal =
            repayAmount == type(uint256).max ? accountBorrowsPrev : repayAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the payer and the repayAmount
         *  On success, the pToken holds an additional repayAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *   it returns the amount actually transferred, in case of a fee.
         */
        uint256 actualRepayAmount = doTransferIn(payer, repayAmountFinal);

        /*
         * We calculate the new borrower and total borrow balances, failing on underflow:
         *  accountBorrowsNew = accountBorrows - actualRepayAmount
         *  totalBorrowsNew = totalBorrows - actualRepayAmount
         */
        uint256 accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
        uint256 totalBorrowsNew = $.totalBorrows - actualRepayAmount;

        /* We write the previously calculated values into storage */
        $.accountBorrows[onBehalfOf].principal = accountBorrowsNew;
        $.accountBorrows[onBehalfOf].interestIndex = $.borrowIndex;
        $.totalBorrows = totalBorrowsNew;

        $.riskEngine.repayBorrowVerify(IPToken(address(this)), onBehalfOf);

        /* We emit a RepayBorrow event */
        emit RepayBorrow(
            payer, onBehalfOf, actualRepayAmount, accountBorrowsNew, totalBorrowsNew
        );

        return actualRepayAmount;
    }

    /**
     * @notice The liquidator liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this pToken to be liquidated
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param pTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     */
    function liquidateBorrowFresh(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        IPToken pTokenCollateral
    ) internal {
        /* Fail if liquidate not allowed */
        RiskEngineError.Error allowed = _getPTokenStorage()
            .riskEngine
            .liquidateBorrowAllowed(
            address(this), address(pTokenCollateral), borrower, repayAmount
        );
        require(
            allowed == RiskEngineError.Error.NO_ERROR,
            PTokenError.LiquidateRiskEngineRejection(uint256(allowed))
        );

        /* Verify market's block timestamp equals current block timestamp */
        require(
            _getPTokenStorage().accrualBlockTimestamp == _getBlockTimestamp(),
            PTokenError.LiquidateFreshnessCheck()
        );

        /* Verify pTokenCollateral market's block timestamp equals current block timestamp */
        require(
            pTokenCollateral.accrualBlockTimestamp() == _getBlockTimestamp(),
            PTokenError.LiquidateCollateralFreshnessCheck()
        );

        /* Fail if borrower = liquidator */
        require(borrower != liquidator, PTokenError.LiquidateLiquidatorIsBorrower());

        /* Fail if repayAmount = 0 */
        require(repayAmount != 0, PTokenError.LiquidateCloseAmountIsZero());

        /* Fail if repayAmount = type(uint256).max */
        require(
            repayAmount != type(uint256).max, PTokenError.LiquidateCloseAmountIsUintMax()
        );

        /* Fail if repayBorrow fails */
        uint256 actualRepayAmount = repayBorrowFresh(liquidator, borrower, repayAmount);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We calculate the number of collateral tokens that will be seized */
        (RiskEngineError.Error amountSeizeError, uint256 seizeTokens) = _getPTokenStorage(
        ).riskEngine.liquidateCalculateSeizeTokens(
            borrower, address(this), address(pTokenCollateral), actualRepayAmount
        );
        require(
            amountSeizeError == RiskEngineError.Error.NO_ERROR,
            PTokenError.LiquidateCalculateAmountSeizeFailed(uint256(amountSeizeError))
        );

        /* Revert if borrower collateral token balance < seizeTokens */
        require(
            pTokenCollateral.balanceOf(borrower) >= seizeTokens,
            PTokenError.LiquidateSeizeTooMuch()
        );

        // If this is also the collateral, run seizeInternal to avoid re-entrancy, otherwise make an external call
        if (address(pTokenCollateral) == address(this)) {
            seizeInternal(address(this), liquidator, borrower, seizeTokens);
        } else {
            pTokenCollateral.seize(liquidator, borrower, seizeTokens);
        }

        /* We emit a LiquidateBorrow event */
        emit LiquidateBorrow(
            liquidator,
            borrower,
            actualRepayAmount,
            address(pTokenCollateral),
            seizeTokens
        );
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another pToken.
     *  Its absolutely critical to use msg.sender as the seizer pToken and not a parameter.
     * @param seizerToken The contract seizing the collateral (i.e. borrowed pToken)
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of pTokens to seize
     */
    function seizeInternal(
        address seizerToken,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) internal {
        PTokenData storage $ = _getPTokenStorage();
        /* Fail if seize not allowed */
        RiskEngineError.Error allowed =
            $.riskEngine.seizeAllowed(address(this), seizerToken);
        require(
            allowed == RiskEngineError.Error.NO_ERROR,
            PTokenError.LiquidateSeizeRiskEngineRejection(uint256(allowed))
        );

        /*
         * We calculate the new borrower and liquidator token balances, failing on underflow/overflow:
         *  borrowerTokensNew = accountTokens[borrower] - seizeTokens
         *  liquidatorTokensNew = accountTokens[liquidator] + seizeTokens
         */
        uint256 protocolSeizeTokens =
            seizeTokens.mul_($.protocolSeizeShareMantissa.toExp());
        uint256 liquidatorSeizeTokens = seizeTokens - protocolSeizeTokens;

        uint256 accumulatedReserve =
            exchangeRateStoredInternal().toExp().mul_ScalarTruncate(protocolSeizeTokens);

        (uint256 ownerShare, uint256 configuratorShare) =
            _getReserveShares(accumulatedReserve);
        uint256 totalReservesNew = $.totalReserves + accumulatedReserve;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the calculated values into storage */
        $.totalReserves = totalReservesNew;
        $.ownerReserves += ownerShare;
        $.configuratorReserves += configuratorShare;
        $.totalSupply -= protocolSeizeTokens;
        $.accountTokens[borrower] -= seizeTokens;
        $.accountTokens[liquidator] += liquidatorSeizeTokens;

        /* Emit a Transfer event */
        emit Transfer(borrower, liquidator, liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), protocolSeizeTokens);
        emit ReservesAdded(address(this), accumulatedReserve, totalReservesNew);
    }

    /**
     * @dev Similar to ERC-20 transfer, but handles tokens that have transfer fees.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     * @param from Sender of the underlying tokens
     * @param amount Amount of underlying to transfer
     * @return Actual amount received
     */
    function doTransferIn(address from, uint256 amount)
        internal
        virtual
        returns (uint256)
    {
        // Read from storage once
        IERC20 token = IERC20(_getPTokenStorage().underlying);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 balanceAfter = token.balanceOf(address(this));
        // Return the amount that was *actually* transferred
        return balanceAfter - balanceBefore;
    }

    /**
     * @dev Similar to ERC20 transfer, and reverts on failure.
     * @param to Receiver of the underlying tokens
     * @param amount Amount of underlying to transfer
     */
    function doTransferOut(address to, uint256 amount) internal virtual {
        IERC20(_getPTokenStorage().underlying).safeTransfer(to, amount);
    }

    /**
     * @notice Transfer `tokens` tokens from `src` to `dst` by `spender`
     * @dev Called by both `transfer` and `transferFrom` internally
     * @param spender The address of the account performing the transfer
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param tokens The number of tokens to transfer
     */
    function _transferTokens(address spender, address src, address dst, uint256 tokens)
        internal
    {
        require(dst != address(0), CommonError.ZeroAddress());

        PTokenData storage $ = _getPTokenStorage();

        /* Fail if transfer not allowed */
        RiskEngineError.Error allowed =
            $.riskEngine.transferAllowed(address(this), src, tokens);
        require(
            allowed == RiskEngineError.Error.NO_ERROR,
            PTokenError.TransferRiskEngineRejection(uint256(allowed))
        );

        /* Do not allow self-transfers */
        require(src != dst, PTokenError.TransferNotAllowed());

        if (spender != src) {
            _spendAllowance(src, spender, tokens);
        }

        /* Do the calculations, checking for {under,over}flow */
        uint256 srcTokensNew = $.accountTokens[src] - tokens;
        uint256 dstTokensNew = $.accountTokens[dst] + tokens;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        $.accountTokens[src] = srcTokensNew;
        $.accountTokens[dst] = dstTokensNew;

        /* We emit a Transfer event */
        emit Transfer(src, dst, tokens);
    }

    /**
     * @dev Updates `owner` allowance for `spender` based on spent `value`.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = _getPTokenStorage().transferAllowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= value,
                PTokenError.InsufficientAllowance(spender, currentAllowance, value)
            );
            unchecked {
                _getPTokenStorage().transferAllowances[owner][spender] =
                    currentAllowance - value;
            }
        }
    }

    /**
     * @notice Sets a new protocol seize share for the protocol
     */
    function _setProtocolSeizeShareMantissa(uint256 newProtocolSeizeShareMantissa)
        internal
    {
        PTokenData storage $ = _getPTokenStorage();

        require(
            newProtocolSeizeShareMantissa + $.reserveFactorMantissa <= _MANTISSA_ONE,
            PTokenError.SetProtocolSeizeShareBoundsCheck()
        );

        uint256 oldProtocolSeizeShareMantissa = $.protocolSeizeShareMantissa;
        $.protocolSeizeShareMantissa = newProtocolSeizeShareMantissa;

        emit NewProtocolSeizeShare(
            oldProtocolSeizeShareMantissa, newProtocolSeizeShareMantissa
        );
    }

    /**
     * @notice Sets a new reserve factor for the protocol (*requires fresh interest accrual)
     * @dev Admin function to set a new reserve factor
     */
    function _setReserveFactorFresh(uint256 newReserveFactorMantissa) internal {
        // Verify market's block timestamp equals current block timestamp
        require(
            _getPTokenStorage().accrualBlockTimestamp == _getBlockTimestamp(),
            PTokenError.SetReserveFactorFreshCheck()
        );

        // Check newReserveFactor ≤ maxReserveFactor
        require(
            newReserveFactorMantissa <= _RESERVE_FACTOR_MAX_MANTISSA,
            PTokenError.SetReserveFactorBoundsCheck()
        );

        uint256 oldReserveFactorMantissa = _getPTokenStorage().reserveFactorMantissa;
        _getPTokenStorage().reserveFactorMantissa = newReserveFactorMantissa;

        emit NewReserveFactor(oldReserveFactorMantissa, newReserveFactorMantissa);
    }

    /**
     * @notice Add reserves by transferring from caller
     * @dev Requires fresh interest accrual
     * @param addAmount Amount of addition to reserves
     */
    function _addReservesFresh(uint256 addAmount) internal {
        // totalReserves + actualAddAmount
        uint256 totalReservesNew;
        uint256 actualAddAmount;
        PTokenData storage $ = _getPTokenStorage();

        // Verify market's block timestamp equals current block timestamp
        require(
            $.accrualBlockTimestamp == _getBlockTimestamp(),
            PTokenError.AddReservesFactorFreshCheck()
        );

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the caller and the addAmount
         *  On success, the pToken holds an additional addAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *  it returns the amount actually transferred, in case of a fee.
         */

        actualAddAmount = doTransferIn(msg.sender, addAmount);

        totalReservesNew = $.totalReserves + actualAddAmount;

        // Store reserves[n+1] = reserves[n] + actualAddAmount
        $.totalReserves = totalReservesNew;

        /* Emit NewReserves(admin, actualAddAmount, reserves[n+1]) */
        emit ReservesAdded(msg.sender, actualAddAmount, totalReservesNew);
    }

    /**
     * @notice Reduces reserves by transferring to admin
     * @dev Requires fresh interest accrual
     * @param reduceAmount Amount of reduction to reserves
     */
    function _reduceReserves(uint256 reduceAmount, uint256 totalReserve)
        internal
        returns (uint256 newReserve)
    {
        accrueInterest();
        // newReserve = totalReserves - reduceAmount

        // Verify market's block timestamp equals current block timestamp
        require(
            _getPTokenStorage().accrualBlockTimestamp == _getBlockTimestamp(),
            PTokenError.ReduceReservesFreshCheck()
        );

        // Fail gracefully if protocol has insufficient underlying cash
        require(getCash() >= reduceAmount, PTokenError.ReduceReservesCashNotAvailable());

        // Check reduceAmount ≤ reserves[n] (totalReserves)
        require(reduceAmount <= totalReserve, PTokenError.ReduceReservesCashValidation());

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        newReserve = totalReserve - reduceAmount;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(msg.sender, reduceAmount);
    }

    function _setRiskEngine(IRiskEngine newRiskEngine) internal {
        IRiskEngine oldRiskEngine = _getPTokenStorage().riskEngine;

        // Set market's riskEngine to newRiskEngine
        _getPTokenStorage().riskEngine = newRiskEngine;

        // Emit NewRiskEngine(oldRiskEngine, newRiskEngine)
        emit NewRiskEngine(oldRiskEngine, newRiskEngine);
    }

    function _pendingAccruedSnapshot()
        internal
        view
        returns (PendingSnapshot memory snapshot)
    {
        PTokenData storage $ = _getPTokenStorage();

        /* Read the previous values out of storage */
        snapshot.totalBorrow = $.totalBorrows;
        snapshot.totalReserve = $.totalReserves;
        snapshot.accBorrowIndex = $.borrowIndex;
        snapshot.ownerReserve = $.ownerReserves;
        snapshot.configuratorReserve = $.configuratorReserves;

        uint256 accruedBlockTimestamp = $.accrualBlockTimestamp;

        if (_getBlockTimestamp() > accruedBlockTimestamp && snapshot.totalBorrow > 0) {
            /* Calculate the current borrow interest rate */
            uint256 borrowRate = IInterestRateModel(address(this)).getBorrowRate(
                getCash(), snapshot.totalBorrow, snapshot.totalReserve
            );

            /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  interestFactor = borrowRate * timeDelta
         *  interestAccumulated = interestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = interestFactor * borrowIndex + borrowIndex
         */

            ExponentialNoError.Exp interestFactor =
                borrowRate.toExp().mul_(_getBlockTimestamp() - accruedBlockTimestamp);

            uint256 interestAccumulated =
                interestFactor.mul_ScalarTruncate(snapshot.totalBorrow);

            uint256 accumulatedReserve =
                $.reserveFactorMantissa.toExp().mul_ScalarTruncate(interestAccumulated);

            (uint256 ownerShare, uint256 configuratorShare) =
                _getReserveShares(accumulatedReserve);

            // Update snapshot values
            snapshot.totalBorrow += interestAccumulated;
            snapshot.totalReserve += accumulatedReserve;
            snapshot.ownerReserve += ownerShare;
            snapshot.configuratorReserve += configuratorShare;
            snapshot.accBorrowIndex = interestFactor.mul_ScalarTruncateAddUInt(
                snapshot.accBorrowIndex, snapshot.accBorrowIndex
            );
        }
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return the calculated balance
     */
    function borrowBalanceStoredInternal(address account)
        internal
        view
        returns (uint256)
    {
        /* Get borrowBalance and borrowIndex */
        BorrowSnapshot memory borrowSnapshot = _getPTokenStorage().accountBorrows[account];

        /* If borrowBalance = 0 then borrowIndex is likely also 0.
         * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
         */
        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        /* Calculate new borrow balance using the interest index:
         *  recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
         */
        return borrowSnapshot.principal * _getPTokenStorage().borrowIndex
            / borrowSnapshot.interestIndex;
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the PToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return calculated exchange rate scaled by 1e18
     */
    function exchangeRateStoredInternal() internal view returns (uint256) {
        uint256 _totalSupply = _getPTokenStorage().totalSupply;
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return _getPTokenStorage().initialExchangeRateMantissa;
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
             */
            uint256 cashPlusBorrowsMinusReserves = getCash()
                + _getPTokenStorage().totalBorrows - _getPTokenStorage().totalReserves;
            return
                cashPlusBorrowsMinusReserves * ExponentialNoError.expScale / _totalSupply;
        }
    }

    /**
     * @dev Function to check if msg.sender is delegatee
     */
    function _isDelegateeOf(address onBehalfOf) internal view {
        require(
            _getPTokenStorage().riskEngine.delegateAllowed(onBehalfOf, msg.sender),
            PTokenError.DelegateNotAllowed()
        );
    }

    /**
     * @dev Function to retrieve the splitted reserve share for owner
     * and configurator based on accumulated reserves
     */
    function _getReserveShares(uint256 accumulatedReserve)
        internal
        view
        returns (uint256 ownerShare, uint256 configuratorShare)
    {
        (uint256 ownerShareMantissa, uint256 configuratorShareMantissa) =
            _getPTokenStorage().riskEngine.getReserveShares();

        // Split reserves between owner and configurator
        ownerShare = ownerShareMantissa.toExp().mul_ScalarTruncate(accumulatedReserve);
        configuratorShare =
            configuratorShareMantissa.toExp().mul_ScalarTruncate(accumulatedReserve);
    }

    /**
     * @dev Function to retrieve current block timestamp
     */
    function _getBlockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool result) {
        assembly ("memory-safe") {
            result := tload(_SLOT_PTOKEN_TRANSIENT_STORAGE)
        }
    }

    /**
     * @dev Checks permission of given role from assigned risk engine
     */
    function _checkPermission(bytes32 permission, address target)
        internal
        view
        override
    {
        require(
            IRBAC(address(_getPTokenStorage().riskEngine)).hasPermission(
                permission, target
            ),
            PermissionDenied(permission, target)
        );
    }
}
