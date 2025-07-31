// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RiskEngineModule, IRiskEngine} from "@modules/riskEngine/RiskEngineModule.sol";

contract TestStructs {
    struct ActionParameters {
        Action action;
        address pToken;
        address tokenAddress;
        uint256 amount;
        bool expectRevert;
        bytes error;
        address prankAddress;
        address onBehalfOf;
    }

    struct TransferParameters {
        address pToken;
        address receiver;
        uint256 amount;
        bool expectRevert;
        bytes error;
        address prankAddress;
        address onBehalfOf;
    }

    struct ActionStateData {
        PTokenData pTokenData;
        UserData userData;
    }

    struct PTokenData {
        uint256 totalCash;
        uint256 totalBorrow;
        uint256 totalReserve;
        uint256 totalSupply;
        uint256 totalSupplyUnderlying;
    }

    struct UserData {
        uint256 underlyingBalance;
        uint256 collateral;
        uint256 borrowed;
    }

    struct LiquidationStateParams {
        address prankAddress;
        address userToLiquidate;
        address collateralPToken;
        address borrowedPToken;
        address underlyingRepayToken;
    }

    struct LiquidationParams {
        address prankAddress;
        address userToLiquidate;
        address collateralPToken;
        address borrowedPToken;
        uint256 repayAmount;
        bool expectRevert;
        bytes error;
    }

    struct LiquidationStateData {
        UserData prankAddressData;
        UserData userToLiquidateData;
        PTokenData collateralPTokenData;
        PTokenData borrowedPTokenData;
    }

    struct PTokenInitialization {
        address underlying;
        IRiskEngine riskEngine;
        uint256 initialExchangeRate;
        uint256 reserveFactor;
        uint256 protocolSeizeShare;
        uint256 borrowRateMax;
        string name;
        string symbol;
        uint8 pTokenDecimals;
    }

    enum Action {
        MINT,
        SUPPLY,
        WITHDRAW,
        WITHDRAW_UNDERLYING,
        BORROW,
        REPAY,
        LIQUIDATE
    }
}
