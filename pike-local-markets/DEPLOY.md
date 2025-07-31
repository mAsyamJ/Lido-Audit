# Deployment Guide for Pike Protocol

This guide explains how to deploy the Pike Protocol ecosystem using two main scripts:

1. `cannon-deploy.sh` - For deploying the factory contract
2. `config-action.sh` - For deploying protocols, markets, and E-Modes

The deployment process follows a two-stage approach where the factory is deployed first using Cannon, and then protocols/markets/E-Modes are deployed through the factory using the configuration-based action scripts.

## Prerequisites

1. **Install Dependencies**:

   - Ensure you have [Foundry](https://book.getfoundry.sh/) installed.
   - Install Cannon for factory deployment (see [Cannon Documentation](https://usecannon.com/)).

2. **Single Factory per Chain**:

   - Each chain has one factory contract managing all protocols and markets. This factory is deployed **once per chain** using the `cannon-deploy.sh` script.
   - After Cannon deployment, the factory address is written to `deployments/<version>/<chain>/factory.Proxy.json`.

3. **Configuration Files**:
   - Before running any deployment script, prepare a JSON config file in `script/configs/<chain>/protocol-<protocol-id>.json`.
   - The config file must include specific sections depending on the script you're running:
     - **`DeployProtocol`**: Requires `protocol-info`.
     - **`DeployMarket`**: Requires `market-*` entries.
     - **`ConfigureEMode`**: Requires `emode-*` entries.

## Part 1: Factory Deployment with `cannon-deploy.sh`

The `cannon-deploy.sh` script deploys the factory contract, which is the foundation for all Pike Protocol deployments on a given chain.

### Script Options

```
Usage: ./script/cannon/cannon-deploy.sh [options]
Options:
  -h, --help                 Show this help message
  -d, --dry-run              Enable dry run mode
  -v, --version VERSION      Specify deployment version (default: 1.0.0)
  -c, --chains CHAIN1,CHAIN2 Specify chains to deploy (comma-separated)
  -s, --skip CHAIN1,CHAIN2   Skip specified chains (comma-separated)
  -p, --private-key KEY      Specify private key for deployments
  -n, --network NETWORK      Specify network type: mainnet or testnet (default: testnet)
```

### Available Chains

- **Mainnet chains**: base-mainnet, arb-mainnet, op-mainnet
- **Testnet chains**: base-sepolia, arb-sepolia, op-sepolia, monad-testnet, bera-bepolia

### Deployment Steps

1. **Prepare Cannon Configuration**:

   - Ensure your Cannon configuration is set up in `script/cannon/<chain>/<chain>.toml`.

2. **Run the Deployment**:

   ```bash
   ./script/cannon/cannon-deploy.sh \
     --version 1.0.0 \
     --chains base-sepolia \
     --network testnet \
     --private-key YOUR_PRIVATE_KEY
   ```

   For a dry run (no actual deployment):

   ```bash
   ./script/cannon/cannon-deploy.sh \
     --dry-run \
     --version 1.0.0 \
     --chains base-sepolia \
     --network testnet
   ```

3. **Verify Deployment**:
   - Check `deployments/<version>/<chain>/factory.Proxy.json` for the factory address.
   - For dry runs, check `deployments/<version>/<chain>/dry-run/`.

### Important Notes

- The script will create backups of existing deployments before overwriting them.
- You can deploy to multiple chains by specifying comma-separated values: `--chains base-sepolia,arb-sepolia`.

## Part 2: Protocol Deployment with `config-action.sh`

After deploying the factory, use `config-action.sh` to deploy protocols, markets, and E-Modes.

### Config File Preparation

The config file must be structured correctly for each deployment type.

```json
{
  "protocol-info": {
    "..."
  },
  "market-weth": {
    "..."
  },
  "emode-1": {
    "..."
  }
}
```

- **`protocol-info`**: Required for `DeployProtocol`. Defines governance and share settings.
- **`market-*`**: Required for `Market`. Each market (e.g., `market-usdc`) specifies token and risk parameters.
- **`emode-*`**: Required for `EMode`. Each E-Mode (e.g., `emode-1`) specifies pTokens and permissions.

### Deployment Sequence

The typical deployment sequence is:

1. Deploy a protocol using `config-action.sh` with `DeployProtocol.s.sol`
2. Deploy markets using `config-action.sh` with `Market.s.sol`
3. Configure E-Modes using `config-action.sh` with `EMode.s.sol`

### 1. Deploy a Protocol

Deploy a new protocol, which increments the protocol count in the factory. Below is an example for `base-sepolia` with protocol ID `1`:

**Requirements**:

- Config file must include `protocol-info`.
- Factory must already be deployed via `cannon-deploy.sh`.

**Command**:

```bash
./script/actions/config-action.sh \
  --script script/actions/DeployProtocol.s.sol \
  --version 1.0.0 \
  --protocol-id 1 \
  --chains base-sepolia \
  --broadcast \
  --private-key YOUR_PRIVATE_KEY
```

**Output**:

- Creates `deployments/1.0.0/base-sepolia/dry-run/protocol-1/deploymentData.json` (dry run) or `deployments/1.0.0/base-sepolia/protocol-1/deploymentData.json` (broadcast).
- Logs deployment details to `logs/1.0.0/base-sepolia/`.

**Notes**:

- The script checks the factory's `protocolCount` and assigns the next ID. The `--protocol-id` must match this expected ID.
- Each deployment adds a new protocol to the factory's list.

### 2. Deploy Markets

Deploy markets for an existing protocol.

**Requirements**:

- Config file must include `market-*` entries.
- Protocol must already be deployed (i.e., `deploymentData.json` exists).

**Command**:

```bash
./script/actions/config-action.sh \
  --script script/actions/Market.s.sol \
  --version 1.0.0 \
  --protocol-id 1 \
  --chains base-sepolia \
  --broadcast \
  --private-key YOUR_PRIVATE_KEY
```

**Output**:

- Updates `deploymentData.json` with market addresses (e.g., `"market-pusdc": "0x..."`).
- Skips markets already listed in `deploymentData.json`.

### 3. Configure E-Modes

Configure E-Modes for an existing protocol.

**Requirements**:

- Config file must include `emode-*` entries.
- Protocol and relevant markets must be deployed (pToken addresses must be valid).

**Command**:

```bash
./script/actions/config-action.sh \
  --script script/actions/EMode.s.sol \
  --version 1.0.0 \
  --protocol-id 1 \
  --chains base-sepolia \
  --broadcast \
  --private-key YOUR_PRIVATE_KEY
```

**Output**:

- Creates `emode-1.json`, etc., in `deployments/1.0.0/base-sepolia/protocol-1/`.
- Skips E-Modes if their files already exist.

## Security Notes

1. **Do Not Manually Edit Deployment Files**:

   - The scripts write to `deploymentData.json` and other files based on the current state of the factory.
   - Manual edits can cause mismatches with on-chain state, leading to deployment failures or incorrect configurations.
   - The scripts check existing data to prevent duplicates and ensure consistency.

2. **Factory Deployment Safety**:

   - The factory is a singleton per chain, managing all protocols and markets.
   - The `cannon-deploy.sh` script creates backups of existing deployments when overwriting.

3. **Deployment Verification**:
   - Always check the logs and output files to verify successful deployments.
   - For `cannon-deploy.sh`, verify factory address in `factory.Proxy.json`.
   - For protocol deployments, check `deploymentData.json` and other output files.

## Troubleshooting

- **Missing Config File**: Ensure the config file exists at `script/configs/<chain>/protocol-<protocol-id>.json`.
- **Protocol ID Mismatch**: Check the factory’s `protocolCount` on-chain to confirm the next ID.
- **Factory Not Found**: Verify `deployments/<version>/<chain>/factory.Proxy.json` exists from the Cannon deployment.
