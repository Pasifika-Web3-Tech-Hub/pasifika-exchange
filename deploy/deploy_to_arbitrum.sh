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
export USDC_ADDRESS=${USDC_ADDRESS:-"0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"}  # Arbitrum Sepolia USDC
export LINK_TOKEN_ADDRESS=${LINK_ADDRESS:-"0xb1D4538B4571d411F07960EF2838Ce337FE1E80E"}  # Arbitrum Sepolia LINK
export CHAINLINK_ORACLE_ADDRESS=${CHAINLINK_ORACLE_ADDRESS:-"0x9f4e3da1d1a089b8d2e5320f4c1114631b5363dd"}  # Default Oracle
export TREASURY_ADDRESS=${TREASURY_ADDRESS:-"0xE1a0Ae0FC16CfC6ABf251c9e7FCf6b6B9bde9aAA"}  # Default Treasury
export CHAINLINK_CIRCLE_JOB_ID=${CHAINLINK_CIRCLE_JOB_ID:-"3862306630303966616335343461653938626633386166363935383735316664"}
export CHAINLINK_STRIPE_JOB_ID=${CHAINLINK_STRIPE_JOB_ID:-"1234567890123456789012345678901234567890123456789012345678901234"}
export CHAINLINK_FEE=${CHAINLINK_FEE:-"1000000000000000000"}  # 1 LINK

# Deploy the price feed contract
echo "Deploying PasifikaPriceFeed..."
forge script script/DeployPasifikaPriceFeed.s.sol --rpc-url $RPC_URL --account $WALLET_ALIAS --broadcast $VERIFY -vvv | tee "$DEPLOYMENT_LOG"

# Capture the deployed address from the deployment log
PRICE_FEED_ADDRESS=$(grep -oP "PasifikaPriceFeed deployed at: \K0x[a-fA-F0-9]{40}" "$DEPLOYMENT_LOG" | tail -1)

if [ -z "$PRICE_FEED_ADDRESS" ]; then
    echo "Failed to extract PasifikaPriceFeed address. Check the deployment log at $DEPLOYMENT_LOG"
    exit 1
fi
echo "PasifikaPriceFeed deployed at: $PRICE_FEED_ADDRESS"

# Deploy the exchange contract
echo "Deploying PasifikaExchange..."
export PRICE_FEED_ADDRESS
export DEPLOY_PRICE_FEED=false
forge script script/DeployPasifikaExchange.s.sol --rpc-url $RPC_URL --account $WALLET_ALIAS --broadcast $VERIFY -vvv | tee -a "$DEPLOYMENT_LOG"

# Capture the deployed address from the deployment log
EXCHANGE_ADDRESS=$(grep -oP "PasifikaExchange deployed at: \K0x[a-fA-F0-9]{40}" "$DEPLOYMENT_LOG" | tail -1)

if [ -z "$EXCHANGE_ADDRESS" ]; then
    echo "Failed to extract PasifikaExchange address. Check the deployment log at $DEPLOYMENT_LOG"
    exit 1
fi
echo "PasifikaExchange deployed at: $EXCHANGE_ADDRESS"

# Deploy the payment gateway
echo "Deploying PasifikaPaymentGateway..."
forge script script/DeployPasifikaPaymentGateway.s.sol --rpc-url $RPC_URL --account $WALLET_ALIAS --broadcast $VERIFY -vvv | tee -a "$DEPLOYMENT_LOG"

# Capture the deployed address from the deployment log
PAYMENT_GATEWAY_ADDRESS=$(grep -oP "PasifikaPaymentGateway deployed at: \K0x[a-fA-F0-9]{40}" "$DEPLOYMENT_LOG" | tail -1)

if [ -z "$PAYMENT_GATEWAY_ADDRESS" ]; then
    echo "Failed to extract PasifikaPaymentGateway address. Check the deployment log at $DEPLOYMENT_LOG"
    exit 1
fi
echo "PasifikaPaymentGateway deployed at: $PAYMENT_GATEWAY_ADDRESS"

# Set environment variable for the payment gateway
export PAYMENT_GATEWAY_ADDRESS=$PAYMENT_GATEWAY_ADDRESS
export DEPLOY_PAYMENT_GATEWAY=false

# Now deploy the Fiat Bridge contract
echo "Deploying PasifikaFiatBridge..."
forge script script/DeployPasifikaFiatBridge.s.sol --rpc-url $RPC_URL --account $WALLET_ALIAS --broadcast $VERIFY -vvv | tee -a "$DEPLOYMENT_LOG"

# Capture the deployed address from the deployment log
FIAT_BRIDGE_ADDRESS=$(grep -oP "PasifikaFiatBridge deployed at: \K0x[a-fA-F0-9]{40}" "$DEPLOYMENT_LOG" | tail -1)

if [ -z "$FIAT_BRIDGE_ADDRESS" ]; then
    echo "Failed to extract PasifikaFiatBridge address. Check the deployment log at $DEPLOYMENT_LOG"
    exit 1
fi
echo "PasifikaFiatBridge deployed at: $FIAT_BRIDGE_ADDRESS"

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

# Create PasifikaPaymentGateway JSON
cat > "$DEPLOYED_CONTRACTS_DIR/PasifikaPaymentGateway.json" << EOL
{
  "name": "PasifikaPaymentGateway",
  "address": "$PAYMENT_GATEWAY_ADDRESS",
  "network": "$NETWORK",
  "explorer": "${EXPLORER_URL}${PAYMENT_GATEWAY_ADDRESS}",
  "deployed": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "description": "Payment processing gateway for the Pasifika Exchange on Arbitrum"
}
EOL

# Create PasifikaFiatBridge JSON
cat > "$DEPLOYED_CONTRACTS_DIR/PasifikaFiatBridge.json" << EOL
{
  "name": "PasifikaFiatBridge",
  "address": "$FIAT_BRIDGE_ADDRESS",
  "network": "$NETWORK",
  "explorer": "${EXPLORER_URL}${FIAT_BRIDGE_ADDRESS}",
  "deployed": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "description": "Fiat-to-crypto bridge with multi-processor support (Circle & Stripe) for the Pasifika Exchange"
}
EOL

# Copy ABIs to the frontend
echo "Copying ABIs to frontend..."
cp out/PasifikaPriceFeed.sol/PasifikaPriceFeed.json "$DEPLOYED_CONTRACTS_DIR/PasifikaPriceFeed_ABI.json"
cp out/PasifikaExchange.sol/PasifikaExchange.json "$DEPLOYED_CONTRACTS_DIR/PasifikaExchange_ABI.json"
cp out/PasifikaPaymentGateway.sol/PasifikaPaymentGateway.json "$DEPLOYED_CONTRACTS_DIR/PasifikaPaymentGateway_ABI.json"
cp out/PasifikaFiatBridge.sol/PasifikaFiatBridge.json "$DEPLOYED_CONTRACTS_DIR/PasifikaFiatBridge_ABI.json"

echo "============================================="
echo "Deployment completed successfully!"
echo "PasifikaPriceFeed deployed at: $PRICE_FEED_ADDRESS"
echo "PasifikaExchange deployed at: $EXCHANGE_ADDRESS"
echo "PasifikaPaymentGateway deployed at: $PAYMENT_GATEWAY_ADDRESS"
echo "PasifikaFiatBridge deployed at: $FIAT_BRIDGE_ADDRESS"
echo "Contract files have been copied to: $DEPLOYED_CONTRACTS_DIR"
echo "Deployment log saved at: $DEPLOYMENT_LOG"
echo "============================================="
