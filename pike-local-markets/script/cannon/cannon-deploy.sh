#!/bin/bash

# Default options
DRY_RUN=false
VERSION="1.0.0"
PRIVATE_KEY=""
NETWORK="testnet"  # Default to testnet
UPGRADE=false      # New flag for upgrade mode

# Chain configurations
# Format: [network]-[chain]
MAINNET_CHAINS=("base-mainnet" "arb-mainnet" "op-mainnet" "sonic-mainnet")
MAINNET_CHAIN_IDS=(8453 42161 10 146)

TESTNET_CHAINS=("base-sepolia" "arb-sepolia" "op-sepolia" "monad-testnet" "bera-bepolia" "sonic-testnet" "unichain-sepolia")
TESTNET_CHAIN_IDS=(84532 421614 11155420 10143 80069 57054 1301)

# Set active chains based on default network
if [[ "$NETWORK" == "mainnet" ]]; then
    CHAINS=("${MAINNET_CHAINS[@]}")
    CHAIN_IDS=("${MAINNET_CHAIN_IDS[@]}")
else
    CHAINS=("${TESTNET_CHAINS[@]}")
    CHAIN_IDS=("${TESTNET_CHAIN_IDS[@]}")
fi

SELECTED_CHAINS=()
SKIP_CHAINS=()

# Function to display help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -d, --dry-run              Enable dry run mode"
    echo "  -u, --upgrade              Use global.toml for upgrades instead of chain-specific TOML"
    echo "  -v, --version VERSION      Specify deployment version (default: $VERSION)"
    echo "  -c, --chains CHAIN1,CHAIN2 Specify chains to deploy (comma-separated)"
    echo "  -s, --skip CHAIN1,CHAIN2   Skip specified chains (comma-separated)"
    echo "  -p, --private-key KEY      Specify private key for deployments"
    echo "  -n, --network NETWORK      Specify network type: mainnet or testnet (default: $NETWORK)"
    
    echo ""
    echo "Available mainnet chains: ${MAINNET_CHAINS[*]}"
    echo "Available testnet chains: ${TESTNET_CHAINS[*]}"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            show_help
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -u|--upgrade)
            UPGRADE=true
            shift
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -c|--chains)
            IFS=',' read -r -a INPUT_CHAINS <<< "$2"
            VALID_CHAINS=()
            for selected in "${INPUT_CHAINS[@]}"; do
                chain_found=false
                for available in "${CHAINS[@]}"; do
                    if [[ "$selected" == "$available" ]]; then
                        VALID_CHAINS+=("$selected")
                        chain_found=true
                        break
                    fi
                done
                if [[ "$chain_found" == "false" ]]; then
                    echo "Error: Chain '$selected' not found in $NETWORK network."
                    echo "Available chains for $NETWORK: ${CHAINS[*]}"
                    other_network_chains=()
                    if [[ "$NETWORK" == "mainnet" ]]; then
                        other_network_chains=("${TESTNET_CHAINS[@]}")
                        echo "Note: '$selected' might be a testnet chain. Use --network testnet if intended."
                    else
                        other_network_chains=("${MAINNET_CHAINS[@]}")
                        echo "Note: '$selected' might be a mainnet chain. Use --network mainnet if intended."
                    fi
                    for other_chain in "${other_network_chains[@]}"; do
                        if [[ "$selected" == "$other_chain" ]]; then
                            echo "Found '$selected' in the other network."
                            break
                        fi
                    done
                fi
            done
            SELECTED_CHAINS=("${VALID_CHAINS[@]}")
            if [[ ${#SELECTED_CHAINS[@]} -eq 0 ]]; then
                echo "Error: No valid chains selected for $NETWORK network"
                exit 1
            fi
            shift 2
            ;;
        -s|--skip)
            IFS=',' read -r -a SKIP_CHAINS <<< "$2"
            shift 2
            ;;
        -p|--private-key)
            PRIVATE_KEY="$2"
            shift 2
            ;;
        -n|--network)
            NETWORK="$2"
            if [[ "$NETWORK" != "mainnet" && "$NETWORK" != "testnet" ]]; then
                echo "Error: Network must be either 'mainnet' or 'testnet'"
                exit 1
            fi
            if [[ "$NETWORK" == "mainnet" ]]; then
                CHAINS=("${MAINNET_CHAINS[@]}")
                CHAIN_IDS=("${MAINNET_CHAIN_IDS[@]}")
            else
                CHAINS=("${TESTNET_CHAINS[@]}")
                CHAIN_IDS=("${TESTNET_CHAIN_IDS[@]}")
            fi
            if [[ ${#SELECTED_CHAINS[@]} -gt 0 ]]; then
                echo "Re-validating selected chains for new network: $NETWORK"
                TEMP_CHAINS=("${SELECTED_CHAINS[@]}")
                SELECTED_CHAINS=()
                for selected in "${TEMP_CHAINS[@]}"; do
                    chain_found=false
                    for available in "${CHAINS[@]}"; do
                        if [[ "$selected" == "$available" ]]; then
                            SELECTED_CHAINS+=("$selected")
                            chain_found=true
                            break
                        fi
                    done
                    if [[ "$chain_found" == "false" ]]; then
                        echo "Warning: Chain '$selected' not valid in new $NETWORK network."
                    fi
                done
                if [[ ${#SELECTED_CHAINS[@]} -eq 0 && ${#TEMP_CHAINS[@]} -gt 0 ]]; then
                    echo "Error: None of the previously selected chains are valid in $NETWORK network"
                    echo "Available chains for $NETWORK: ${CHAINS[*]}"
                    exit 1
                fi
            fi
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Function to check if a chain should be processed
should_process_chain() {
    local chain=$1
    if [[ ${#SELECTED_CHAINS[@]} -gt 0 ]]; then
        for selected in "${SELECTED_CHAINS[@]}"; do
            if [[ "$selected" == "$chain" ]]; then
                for skip in "${SKIP_CHAINS[@]}"; do
                    if [[ "$skip" == "$chain" ]]; then
                        return 1
                    fi
                done
                return 0
            fi
        done
        return 1
    else
        for skip in "${SKIP_CHAINS[@]}"; do
            if [[ "$skip" == "$chain" ]]; then
                return 1
            fi
        done
        return 0
    fi
}

# Function to get chain ID for a given chain
get_chain_id() {
    local chain=$1
    for i in "${!CHAINS[@]}"; do
        if [[ "${CHAINS[$i]}" == "$chain" ]]; then
            echo "${CHAIN_IDS[$i]}"
            return
        fi
    done
    echo "Unknown"
}

# Check if private key is needed and not provided
if [[ "$DRY_RUN" == "false" && -z "$PRIVATE_KEY" ]]; then
    echo -n "Enter private key for deployments: "
    read -s PRIVATE_KEY
    echo
    if [[ -z "$PRIVATE_KEY" ]]; then
        echo "Error: Private key is required for non-dry-run deployments"
        exit 1
    fi
fi

# Run the deployments
echo "Starting deployments with version: $VERSION"
echo "Network: $NETWORK"
echo "Dry run mode: $DRY_RUN"
echo "Upgrade mode: $UPGRADE"
echo "Available chains: ${CHAINS[*]}"
if [[ ${#SELECTED_CHAINS[@]} -gt 0 ]]; then
    echo "Selected chains: ${SELECTED_CHAINS[*]}"
fi
if [[ ${#SKIP_CHAINS[@]} -gt 0 ]]; then
    echo "Skipped chains: ${SKIP_CHAINS[*]}"
fi
if [[ "$DRY_RUN" == "false" ]]; then
    echo "Private key: ${PRIVATE_KEY:0:6}...${PRIVATE_KEY: -4} (partially hidden for security)"
fi

# Function to check if deployment already exists
deployment_exists() {
    local version=$1
    local chain=$2
    local is_dry_run=$3
    local path
    if [[ "$is_dry_run" == "true" ]]; then
        path="./deployments/$version/$chain/dry-run"
    else
        path="./deployments/$version/$chain"
        if [[ ! -d "$path" ]]; then
            return 1
        fi
        if [[ $(ls -A "$path" | grep -v "dry-run") ]]; then
            return 0
        else
            return 1
        fi
    fi
    if [[ -d "$path" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to get user confirmation
confirm_overwrite() {
    local version=$1
    local chain=$2
    local is_dry_run=$3
    local path_desc
    if [[ "$is_dry_run" == "true" ]]; then
        path_desc="$chain/dry-run"
    else
        path_desc="$chain"
    fi
    read -p "Deployment for $path_desc with version $version already exists. Overwrite? (y/n): " answer
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        return 0
    else
        return 1
    fi
}

for chain in "${CHAINS[@]}"; do
    if should_process_chain "$chain"; then
        chain_id=$(get_chain_id "$chain")
        
        # Check if deployment already exists
        if deployment_exists "$VERSION" "$chain" "$DRY_RUN"; then
            local path_desc
            if [[ "$DRY_RUN" == "true" ]]; then
                path_desc="$chain/dry-run"
                echo "Note: Existing dry-run deployment for $path_desc with version $VERSION will be overwritten"
            else
                path_desc="$chain"
                echo "Warning: Deployment for $path_desc with version $VERSION already exists."
                if ! confirm_overwrite "$VERSION" "$chain" "$DRY_RUN"; then
                    echo "Skipping deployment for $chain to avoid overwriting"
                    continue
                fi
                timestamp=$(date +%Y%m%d_%H%M%S)
                backup_path="./deployments/${VERSION}_backup_${timestamp}/$chain"
                src_path="./deployments/$VERSION/$chain"
                mkdir -p "$(dirname "$backup_path")"
                echo "Backing up existing deployment to $backup_path"
                cp -r "$src_path" "$(dirname "$backup_path")"
            fi
        fi
        
        # Determine which TOML file to use based on UPGRADE flag
        if [[ "$UPGRADE" == "true" ]]; then
            cmd="cannon build script/cannon/global.toml --chain-id $chain_id"
            echo "Running upgrade deployment with global.toml for $chain"
        else
            cmd="cannon build script/cannon/$chain/$chain.toml --chain-id $chain_id"
            echo "Running standard deployment with $chain/$chain.toml"
        fi
        
        # Set deployment path
        if [[ "$DRY_RUN" == "true" ]]; then
            deploy_path="./deployments/$VERSION/$chain/dry-run"
            mkdir -p "$(dirname "$deploy_path")"
            cmd="$cmd --dry-run -w $deploy_path"
        else
            deploy_path="./deployments/$VERSION/$chain"
            cmd="$cmd --private-key $PRIVATE_KEY -w $deploy_path"
        fi
        
        echo "Running: $cmd"
        eval "$cmd"
        
        # Check if the command was successful
        if [[ $? -eq 0 ]]; then
            echo "Deployment for $chain completed successfully"
        else
            echo "Deployment for $chain failed"
        fi
    else
        echo "Skipping deployment for $chain"
    fi
done

echo "All deployments completed"