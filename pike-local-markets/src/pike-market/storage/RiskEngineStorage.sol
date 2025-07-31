//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPToken} from "@interfaces/IPToken.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {ExponentialNoError} from "@utils/ExponentialNoError.sol";

contract RiskEngineStorage {
    /// @custom:storage-location erc7201:pike.LM.RiskEngine
    struct RiskEngineData {
        /**
         * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
         * @dev mapping pToken -> closeFactor
         */
        mapping(address => uint256) closeFactorMantissa;
        /**
         * @notice Per-account mapping of "activated category"
         */
        mapping(address => uint8) accountCategory;
        /**
         * @notice Per-account mapping of "assets you are in"
         */
        mapping(address => IPToken[]) accountAssets;
        /**
         * @notice Per-category mapping of "markets for collateral"
         * mapping of categoryId -> ptokens -> exist
         */
        mapping(uint8 => mapping(address => bool)) collateralCategory;
        /**
         * @notice Per-category mapping of "markets for borrow"
         * mapping of categoryId -> ptokens -> exist
         */
        mapping(uint8 => mapping(address => bool)) borrowCategory;
        /**
         * @notice mapping of pTokens -> Market metadata
         * @dev Used e.g. to determine if a market is supported
         */
        mapping(address => Market) markets;
        /**
         * @notice mapping of categoryIds -> E-mode metadata
         * @dev Used e.g. to determine if a e-mode is allowed
         */
        mapping(uint8 => EModeConfiguration) emodes;
        /// @notice oracle engine address
        address oracle;
        /// @notice A flag indicating whether transfers are paused by guardian.
        bool transferGuardianPaused;
        /// @notice A flag indicating whether the seize function is paused by guardian.
        bool seizeGuardianPaused;
        /// @notice A flag indicating whether the mint is paused for specific ptoken by guardian.
        mapping(address => bool) mintGuardianPaused;
        /// @notice A flag indicating whether the borrow is paused for specific ptoken by guardian.
        mapping(address => bool) borrowGuardianPaused;
        /// @notice Borrow caps enforced by borrowAllowed for each pToken address.
        ///  Defaults to zero which corresponds to unlimited borrowing.
        mapping(address => uint256) borrowCaps;
        /// @notice Supply caps enforced by mintAllowed for each pToken address.
        ///  Defaults to zero which corresponds to minting not allowed
        mapping(address => uint256) supplyCaps;
        /// @notice Whether the delegate is allowed to borrow or redeem on behalf of the user
        //mapping(address user => mapping (address delegate => bool approved)) public approvedDelegates;
        mapping(address => mapping(address => bool)) approvedDelegates;
        /// @notice A list of all markets (0 is default category includes all markets)
        mapping(uint8 => IPToken[]) allMarkets;
        /**
         * @notice protocol owner share percentage from reserves
         */
        uint256 ownerShareMantissa;
        /**
         * @notice configurator share percentage from reserves
         */
        uint256 configuratorShareMantissa;
    }

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `pTokenBalance` is the number of pTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        IOracleEngine oracle;
        uint8 accountCategory;
        uint256 sumLiquidity;
        uint256 sumCollateral;
        uint256 sumBorrowPlusEffects;
        uint256 pTokenBalance;
        uint256 borrowBalance;
        uint256 exchangeRateMantissa;
        uint256 oraclePriceMantissa;
        ExponentialNoError.Exp threshold;
        ExponentialNoError.Exp exchangeRate;
        ExponentialNoError.Exp oraclePrice;
        ExponentialNoError.Exp tokensToDenom;
    }

    struct Market {
        // Whether or not this market is listed
        bool isListed;
        // e-mode risk parameters
        IRiskEngine.BaseConfiguration baseConfiguration;
        // Per-market mapping of "accounts in this asset as collateral"
        mapping(address => bool) collateralMembership;
        // Per-market mapping of "accounts in this asset as borrow"
        mapping(address => bool) borrowMembership;
    }

    struct EModeConfiguration {
        // Whether or not this emode is allowed
        bool allowed;
        // e-mode risk parameters
        IRiskEngine.BaseConfiguration baseConfiguration;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.RiskEngine")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_RISK_ENGINE_STORAGE =
        0x045c767dd6aa575c77a2f8d1bda11e214b14b47092bcc4f410a939f824586800;

    // closeFactorMantissa must be strictly greater than this value
    uint256 internal constant _CLOSE_FACTOR_MIN_MANTISSA = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint256 internal constant _CLOSE_FACTOR_MAX_MANTISSA = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint256 internal constant _COLLATERAL_FACTOR_MAX_MANTISSA = 0.9e18; // 0.9

    uint256 internal constant _MANTISSA_ONE = 1e18;

    function _getRiskEngineStorage()
        internal
        pure
        returns (RiskEngineData storage data)
    {
        bytes32 s = _SLOT_RISK_ENGINE_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
