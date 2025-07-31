# Audit Scope and Security Assumptions

## Contracts Overview

The following contracts are within the scope for audit. The project follows a modular design, leveraging upgradeable contracts with specific responsibilities.

### Core Contracts

#### Pike Markets

**Errors** The following libraries define custom error messages used in pike markets:

- `CommonError.sol`
- `IRMError.sol`
- `PTokenError.sol`
- `RiskEngineError.sol`

**Interfaces** These interfaces define the interactions with the system’s modules:

- `IDoubleJumpRateModel.sol`
- `IInterestRateModel.sol`
- `IOwnable.sol`
- `IPToken.sol`
- `IRiskEngine.sol`
- `IRBAC.sol`
- `IUpgrade.sol`

**Modules** handling core logic and business rules:

- `InitialModuleBundle.sol` **Description**: This is the initial module responsible for managing minimal access control and the system’s ability to upgrade (UUPS) implementations. Due to how Cannon handles deployments and upgrades, this module is first deployed independently and then used to call upgrades via the Cannon package. If the bytecode of implementation change, Cannon will handle the upgrade automatically to ensure the deployment reflects the latest version. This rerun of the upgrade process ensures consistent deployments with minimal overhead.
- `InitialModuleBeacon.sol` **Description**: Unlike InitialModuleBundle, which is used for deploying Pike Markets independently via Cannon, the InitialModuleBeacon is designed to integrate seamlessly with the factory contract structure. It facilitates the deployment of new RiskEngine and PToken contracts using the router proxy as the implementation and leveraging the Beacon proxy pattern that eliminates the need for UUPS upgradeability on the router.
- `OwnableModule.sol`
- `RBACModule.sol`
- `UpgradeModule.sol`
- `DoubleJumpRateModel.sol` **Description**: Implements the DoubleJumpRate interest model with two kinks and three ranges of utilization (Encourage, Normal, Discourage).
- `PTokenModule.sol` **Description**: Represents the logic for the protocol’s pToken markets, which users interact with to supply, borrow, and redeem assets. It adheres to the ERC-4626 Vault standard and implemented a reserve distribution mechanism between the Protocol Owner and the Curator as part of the total reserve.
- `RiskEngineModule.sol` **Description**: Enforces risk management by controlling borrow and collateral parameters. It includes an Efficiency Mode feature for correlated assets that enables higher Loan-to-Value (LTV) ratios for specified assets used as collateral or for borrowing (similar to AAVE v3).

**Storage** These contracts store the state variables and manage storage layout for the modules:

- `DoubleJumpRateStorage.sol`
- `OwnableStorage.sol`
- `PTokenStorage.sol`
- `RBACStorage.sol`
- `RiskEngineStorage.sol`
- `UpgradeStorage.sol`

**Utilities** Utility contracts for mathematical operations and mixin:

- `ExponentialNoError.sol` **Description**: This contract is directly sourced from Compound v2 and handles safe mathematical operations such as exponentiation without errors. No changes have been made to the original Compound v2 implementation to ensure reliability.
- `RBACMixin.sol`
- `OwnableMixin.sol`
  **Description**: Mixins allow different modules to know specific storage layout and how to read it and it shares between those.

#### Oracle Contracts

**Oracles**

-`ChainlinkOracleProvider.sol`

- `PythOracleProvider.sol`

- `OracleEngine.sol`

- Interfaces:
  - `IOracleEngine.sol`
  - `IOracleProvider.sol`

#### Governance Contracts

**Timelock**

-`Timelock.sol` **Description**: Similar to the OpenZeppelin Timelock, but includes an EmergencyExecution function that allows bypassing the timelock and execute in a single transaction, intended for use before implementing dual-layer governance model.

**Deployment and Upgrade Mechanism**:
The Oracle and Timelock contracts do not require the router proxy pattern and are implemented directly to Beacon contract.

**Factory**

-`Factory.sol` **Description**: A singleton contract that serves as both the deployer and registry for all deployed markets and pTokens. It utilizes four Beacon contracts to deploy proxies for the RiskEngine, PToken, OracleEngine, and Timelock contracts. it manages the deployment of Timelock contracts, which will later integrate into the dual-layer governance system.

- Interfaces:
  - `IFactory.sol`

## Security Assumptions

The following security assumptions have been considered in the design of the protocol:

1. **Inflation Attack Mitigation**: We assume that pToken markets will not have an empty liquidity state to prevent potential inflation attacks. However to mitigate this risk, the `redeemUnderlying` function includes a double-check mechanism on the exchangeRate to prevent high amounts of `redeemAmount` being processed in an empty market scenario.

2. **Access Control**: The system relies on the `RBACModule` and `OwnableModule` for managing access control, ensuring only authorized users can trigger upgrades or sensitive operations.

3. **Upgradability**: The system’s deployment mechanism for PToken and Risk Engine implementation, managed through Cannon, ensures that upgrades (config) only happen when necessary (i.e., when bytecode or arguments change). The initial module deployment guarantees a clean start for upgrades, preventing redeployment unless specific criteria are met.

4. **Factory**: Handles only the initial setup of pTokens and provides the Curator (Governor) with the necessary permissions to independently configure the oracle, RiskEngine, and pToken risk parameters.

## Post-Audit Changes

### MixBytes Audit (Interim)

After the MixBytes audit, the following changes were implemented alongside fixes for reported issues:

- Auto-enable collateral on first supply:
  - When a user supplies an asset for the first time (i.e., no prior pToken balance), it is now automatically enabled as collateral.
- Event Modifications:
  - Added the Oracle Engine address to the `ProtocolDeployed` event to `deployProtocol` function in the Factory contract.
  - Added the pToken address to the `NewCloseFactor` event in the RiskEngine contract.
- New Getter Function in RiskEngine:

  - Introduced the `emodeMarkets` function to retrieve supported pTokens for a given E-Mode category.
  - This function allows users and integrators to query available collateral and borrow options within a specific E-Mode category.

  ```
    function emodeMarkets(uint8 categoryId)
    external
    view
    returns (address[] memory collateralTokens, address[] memory borrowTokens);
  ```

- Factory Contract Authorization Change:
  - The deployMarket function in the Factory contract now verifies whether the caller has the CONFIGURATOR role on the specified RiskEngine.
  - Previously, this depended on an immutable Timelock contract. The new approach allows for more dynamic protocol management.
