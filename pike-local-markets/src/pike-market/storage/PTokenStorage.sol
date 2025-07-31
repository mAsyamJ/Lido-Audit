//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

contract PTokenStorage {
    /// @custom:storage-location erc7201:pike.LM.PToken
    struct PTokenData {
        /**
         * @notice Underlying asset for this PToken
         */
        address underlying;
        /**
         * @notice ERC20 token name for this token
         */
        string name;
        /**
         * @notice ERC20 token symbol for this token
         */
        string symbol;
        /**
         * @notice ERC20 token decimals for this token
         */
        uint8 decimals;
        /**
         * @notice Contract which oversees pToken operations
         */
        IRiskEngine riskEngine;
        /**
         *  @notice Initial exchange rate used when minting the first PTokens (used when totalSupply = 0)
         */
        uint256 initialExchangeRateMantissa;
        /**
         * @notice Share of seized collateral that is added to reserves
         */
        uint256 protocolSeizeShareMantissa;
        /**
         * @notice Fraction of interest currently set aside for reserves
         */
        uint256 reserveFactorMantissa;
        /**
         * @notice Maximum borrow rate that can ever be applied per second (.0005e16 = .0005%)
         */
        uint256 borrowRateMaxMantissa;
        /**
         * @notice Block timestamp that interest was last accrued at
         */
        uint256 accrualBlockTimestamp;
        /**
         * @notice Accumulator of the total earned interest rate since the opening of the market
         */
        uint256 borrowIndex;
        /**
         * @notice Total amount of outstanding borrows of the underlying in this market
         */
        uint256 totalBorrows;
        /**
         * @notice Total amount of reserves of the underlying held in this market
         */
        uint256 totalReserves;
        /**
         * @notice Total number of tokens in circulation
         */
        uint256 totalSupply;
        /**
         * @notice Total amount of reserves accumulated for owner
         */
        uint256 ownerReserves;
        /**
         * @notice Total amount of reserves accumulated for configurator
         */
        uint256 configuratorReserves;
        /**
         * @notice Official record of token balances for each account
         */
        mapping(address => uint256) accountTokens;
        /**
         * @notice Approved token transfer amounts on behalf of others
         */
        mapping(address => mapping(address => uint256)) transferAllowances;
        /**
         * @notice Mapping of account addresses to outstanding borrow balances
         */
        mapping(address => BorrowSnapshot) accountBorrows;
    }

    /// @custom:storage-location erc7201:pike.LM.PToken.Transient
    struct PTokenTransientData {
        /**
         * @dev Guard variable for re-entrancy checks
         */
        bytes32 _entered;
    }

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    /**
     * @notice Struct for real-time data related with pending accrued interest
     * @param totalBorrow The total outstanding borrowed amount, including all accrued interest.
     * @param totalReserve The total amount of reserves held, typically a portion of interest is set aside by the protocol
     * @param accBorrowIndex The global borrow index used for tracking how much interest has accrued since the last update
     */
    struct PendingSnapshot {
        uint256 totalBorrow;
        uint256 totalReserve;
        uint256 accBorrowIndex;
        uint256 ownerReserve;
        uint256 configuratorReserve;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.PToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_PTOKEN_STORAGE =
        0x0be5863c0c782626615eed72fc4c521bcfabebe439cbc2683e49afadb49a0d00;

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.PToken.Transient")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_PTOKEN_TRANSIENT_STORAGE =
        0x4859f9ae8b7704f1d2bda454afdf52ff1d57def69d8277385db7d84008a1d900;

    uint256 internal constant _MANTISSA_ONE = 1e18;

    // Maximum fraction of interest that can be set aside for reserves
    uint256 internal constant _RESERVE_FACTOR_MAX_MANTISSA = 1e18;

    // Dead share for initial mint
    uint256 internal constant MINIMUM_DEAD_SHARES = 1000;

    function _getPTokenStorage() internal pure returns (PTokenData storage data) {
        bytes32 s = _SLOT_PTOKEN_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
