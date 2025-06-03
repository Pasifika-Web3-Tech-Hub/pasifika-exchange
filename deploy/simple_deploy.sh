#!/bin/bash

# Pasifika Exchange Simple Deployment Script
set -e

# Source environment variables
source .env

# Configuration
FRONTEND_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe"
DEPLOYED_CONTRACTS_DIR="$FRONTEND_DIR/deployed_contracts"
RPC_URL=$ARBITRUM_TESTNET_RPC_URL
WALLET_ALIAS=pasifika-account
NETWORK="arbitrum-sepolia"
EXPLORER_URL="https://sepolia.arbiscan.io/address/"

echo "=== Pasifika Exchange Simple Deployment ==="
echo "RPC URL: $RPC_URL"
echo "Network: $NETWORK"
echo "Wallet: $WALLET_ALIAS"
echo "======================================="

# Make sure the output directory exists
mkdir -p "$DEPLOYED_CONTRACTS_DIR"

# Deploy PasifikaPriceFeed
echo "Deploying PasifikaPriceFeed... (enter password when prompted)"
PRICE_FEED_OUTPUT=$(forge script script/DeployPasifikaPriceFeed.s.sol --rpc-url "$RPC_URL" --account "$WALLET_ALIAS" --broadcast -vvv)

# Extract the contract address
PRICE_FEED_ADDRESS=$(echo "$PRICE_FEED_OUTPUT" | grep -oP "PasifikaPriceFeed deployed at: \K0x[a-fA-F0-9]{40}" || echo "")

if [ -z "$PRICE_FEED_ADDRESS" ]; then
    echo "Failed to extract PasifikaPriceFeed address from output."
    exit 1
fi

echo "PasifikaPriceFeed deployed at: $PRICE_FEED_ADDRESS"

# Set environment variable for the Exchange deployment
export PRICE_FEED_ADDRESS
export DEPLOY_PRICE_FEED=false

# Deploy PasifikaExchange
echo "Deploying PasifikaExchange... (enter password when prompted)"
EXCHANGE_OUTPUT=$(forge script script/DeployPasifikaExchange.s.sol --rpc-url "$RPC_URL" --account "$WALLET_ALIAS" --broadcast -vvv)

# Extract the contract address
EXCHANGE_ADDRESS=$(echo "$EXCHANGE_OUTPUT" | grep -oP "PasifikaExchange deployed at: \K0x[a-fA-F0-9]{40}" || echo "")

if [ -z "$EXCHANGE_ADDRESS" ]; then
    echo "Failed to extract PasifikaExchange address from output."
    exit 1
fi

echo "PasifikaExchange deployed at: $EXCHANGE_ADDRESS"

# Build the project with ABIs
echo "Generating ABIs..."
forge build --extra-output-files abi

# Create JSON files for the frontend
echo "Creating contract files for the frontend..."

# PasifikaPriceFeed JSON
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

# PasifikaExchange JSON
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

echo "==============================================="
echo "Deployment completed successfully!"
echo "PasifikaPriceFeed deployed at: $PRICE_FEED_ADDRESS"
echo "PasifikaExchange deployed at: $EXCHANGE_ADDRESS"
echo "Contract files have been copied to: $DEPLOYED_CONTRACTS_DIR"
echo "==============================================="
