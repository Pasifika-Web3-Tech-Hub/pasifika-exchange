#!/bin/bash

# Pasifika Exchange Deployment Script for Arbitrum
# This script deploys the Pasifika Exchange contracts to Arbitrum networks
# and copies the necessary files to the frontend project

set -e # Exit on any error

# Configuration
NETWORK=${1:-arbitrum-sepolia}  # Use first argument or default to arbitrum-sepolia
FRONTEND_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe"
DEPLOYED_CONTRACTS_DIR="$FRONTEND_DIR/deployed_contracts"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DEPLOYMENT_LOG="deploy/logs/deployment_$TIMESTAMP.log"

# RPC URLs and other sensitive data should be loaded from .env file
if [ -f ".env" ]; then
    echo "Loading environment variables from .env file"
    source .env
else
    echo ".env file not found. Please create one with your private keys and RPC URLs."
    exit 1
fi

# Verify we have the necessary env variables
if [ -z "$ARBITRUM_TESTNET_RPC_URL" ] || [ -z "$WALLET_ALIAS" ]; then
    echo "Missing required environment variables. Please set ARBITRUM_TESTNET_RPC_URL and WALLET_ALIAS"
    exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p deploy/logs

# Network-specific configuration
case $NETWORK in
    arbitrum-mainnet)
        RPC_URL=$ARBITRUM_MAINNET_RPC_URL
        EXPLORER_URL="https://arbiscan.io/address/"
        VERIFY="--verify"
        ETH_USD_FEED="0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612"  # Arbitrum mainnet ETH/USD feed
        ;;
    arbitrum-sepolia)
        RPC_URL=$ARBITRUM_TESTNET_RPC_URL
        EXPLORER_URL="https://sepolia.arbiscan.io/address/"
        VERIFY="--verify"
        ETH_USD_FEED="0x694AA1769357215DE4FAC081bf1f309aDC325306"  # Arbitrum Sepolia ETH/USD feed
        ;;
    *)
        echo "Unsupported network: $NETWORK"
        exit 1
        ;;
esac

echo "=== Pasifika Exchange Deployment to $NETWORK ==="
echo "Deployment started at $(date)"
echo "============================================="

# Build the project
echo "Building project..."
forge build --extra-output-files abi --extra-output-files bin

# Deploy contracts
echo "Deploying PasifikaPriceFeed..."
echo "ETH/USD Feed Address: $ETH_USD_FEED"
export ETH_USD_FEED

# Deploy the contracts using Foundry scripts with wallet alias
PRICE_FEED_OUTPUT=$(forge script script/DeployPasifikaPriceFeed.s.sol --rpc-url $RPC_URL --account $WALLET_ALIAS --broadcast $VERIFY -vvv 2>&1)
echo "$PRICE_FEED_OUTPUT" > "$DEPLOYMENT_LOG"

# Extract price feed address from the output
PRICE_FEED_ADDRESS=$(echo "$PRICE_FEED_OUTPUT" | grep -oP "PasifikaPriceFeed deployed at: \K0x[a-fA-F0-9]{40}")
if [ -z "$PRICE_FEED_ADDRESS" ]; then
    echo "Failed to extract PasifikaPriceFeed address. Check the deployment log at $DEPLOYMENT_LOG"
    exit 1
fi
echo "PasifikaPriceFeed deployed at: $PRICE_FEED_ADDRESS"

# Now deploy the Exchange contract
echo "Deploying PasifikaExchange..."
export PRICE_FEED_ADDRESS
export DEPLOY_PRICE_FEED=false
EXCHANGE_OUTPUT=$(forge script script/DeployPasifikaExchange.s.sol --rpc-url $RPC_URL --account $WALLET_ALIAS --broadcast $VERIFY -vvv 2>&1)
echo "$EXCHANGE_OUTPUT" >> "$DEPLOYMENT_LOG"

# Extract exchange address from the output
EXCHANGE_ADDRESS=$(echo "$EXCHANGE_OUTPUT" | grep -oP "PasifikaExchange deployed at: \K0x[a-fA-F0-9]{40}")
if [ -z "$EXCHANGE_ADDRESS" ]; then
    echo "Failed to extract PasifikaExchange address. Check the deployment log at $DEPLOYMENT_LOG"
    exit 1
fi
echo "PasifikaExchange deployed at: $EXCHANGE_ADDRESS"

# Create JSON files for the frontend
echo "Creating contract files for the frontend..."

# Ensure the destination directory exists
mkdir -p "$DEPLOYED_CONTRACTS_DIR"

# Create PasifikaPriceFeed JSON
cat > "$DEPLOYED_CONTRACTS_DIR/PasifikaPriceFeed.json" << EOL
{
  "name": "PasifikaPriceFeed",
  "address": "$PRICE_FEED_ADDRESS",
  "network": "$NETWORK",
  "explorer": "${EXPLORER_URL}${PRICE_FEED_ADDRESS}",
  "deployed": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "description": "Price feed oracle for the Pasifika Exchange on Arbitrum"
}
EOL

# Create PasifikaExchange JSON
cat > "$DEPLOYED_CONTRACTS_DIR/PasifikaExchange.json" << EOL
{
  "name": "PasifikaExchange",
  "address": "$EXCHANGE_ADDRESS",
  "network": "$NETWORK",
  "explorer": "${EXPLORER_URL}${EXCHANGE_ADDRESS}",
  "deployed": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "description": "Decentralized exchange for Pacific Island communities on Arbitrum"
}
EOL

# Copy ABIs to the frontend
echo "Copying ABIs to frontend..."
cp out/PasifikaPriceFeed.sol/PasifikaPriceFeed.json "$DEPLOYED_CONTRACTS_DIR/PasifikaPriceFeed_ABI.json"
cp out/PasifikaExchange.sol/PasifikaExchange.json "$DEPLOYED_CONTRACTS_DIR/PasifikaExchange_ABI.json"

echo "============================================="
echo "Deployment completed successfully!"
echo "PasifikaPriceFeed deployed at: $PRICE_FEED_ADDRESS"
echo "PasifikaExchange deployed at: $EXCHANGE_ADDRESS"
echo "Contract files have been copied to: $DEPLOYED_CONTRACTS_DIR"
echo "Deployment log saved at: $DEPLOYMENT_LOG"
echo "============================================="
