# Pasifika Web3 Tech Hub - Exchange

<div align="center">
  <img src="./pasifika.png" alt="Pasifika" width="300" height="300" />
  <h2>Building the Future of Pacific Island Web3 Technology</h2>
  <p><em>Established 2025</em></p>
  <hr />
  <p><strong>"If we take care of our own, they will take care of us"</strong></p>
</div>

**Pasifika Exchange is a cross-chain decentralized exchange platform designed specifically for Pacific Island communities with initial deployment on Arbitrum, utilizing Chainlink protocols for reliable price data and cross-chain interoperability.**

## Overview

This project implements a decentralized exchange (DEX) to provide essential trading infrastructure for the Pasifika Web3 Tech Hub. Initially built on Arbitrum to take advantage of its low fees and high throughput, the exchange is designed with cross-chain interoperability in mind and optimized for the needs of Pacific Island users.

### Key Components

-   **PasifikaExchange**: An AMM-style (Automated Market Maker) DEX that allows cross-chain trading between tokens on multiple EVM Compatible networks
-   **PasifikaPriceFeed**: Chainlink oracle integration for reliable token price data in USD
-   **PasifikaCrossChainBridge**: Chainlink CCIP (Cross-Chain Interoperability Protocol) integration enabling secure messaging and token transfers between networks
-   **PasifikaFiatBridge & PaymentGateway**: On-chain fiat payment system supporting multiple payment processors (Circle and Stripe) with Chainlink oracle integration for payment verification
-   **Multi-Network Support**: Initially deployed on Arbitrum with active interoperability for Linea and RootStock

### Technology Stack

The Pasifika Exchange is built with:

-   **Foundry**: Smart contract development framework
-   **Solidity**: Smart contract programming language
-   **Chainlink**: Price feeds, oracles, and CCIP network
-   **OpenZeppelin**: Secure contract implementations
-   **EVM Compatible Networks**: Multiple Layer 2 and sidechain solutions (Arbitrum, Linea, RootStock)
-   **Cross-Chain Interoperability Protocol (CCIP)**: For secure messaging and asset transfers between networks
-   **Fiat Payment Processors**: Integration with Circle and Stripe for multi-currency fiat payments
-   **USDC**: Stablecoin used for on-chain settlement of fiat payments

## Frontend Integration

The deployment script automatically copies contract addresses and ABIs to the Pasifika Web3 frontend at:
```
/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts/
```

### Contract Files Generated

1. `PasifikaPriceFeed.json` - Contains address and metadata
2. `PasifikaExchange.json` - Contains address and metadata
3. `PasifikaCrossChainBridge.json` - Contains address and network configuration data
4. `PasifikaPriceFeed_ABI.json` - Full contract ABI
5. `PasifikaExchange_ABI.json` - Full contract ABI
6. `PasifikaCrossChainBridge_ABI.json` - Full contract ABI

### React Hooks Integration

Create React hooks in your frontend project to interact with the exchange. Example:

```typescript
// /home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/lib/hooks/useExchange.ts

import { useReadContract, useWriteContract } from 'wagmi';
import PasifikaExchangeInfo from '../deployed_contracts/PasifikaExchange.json';
import PasifikaExchangeABI from '../deployed_contracts/PasifikaExchange_ABI.json';

export function useExchange() {
  const { data: pairs } = useReadContract({
    address: PasifikaExchangeInfo.address as `0x${string}`,
    abi: PasifikaExchangeABI as any,
    functionName: 'getLiquidity',
  });
  
  const { writeContract } = useWriteContract();
  
  const swapETHForTokens = async (tokenAddress, minTokens, ethAmount) => {
    return writeContract({
      address: PasifikaExchangeInfo.address as `0x${string}`,
      abi: PasifikaExchangeABI as any,
      functionName: 'swapETHForTokens',
      args: [tokenAddress, minTokens],
      value: ethAmount,
    });
  };
  
  // Add other functions as needed
  
  return {
    pairs,
    swapETHForTokens,
    // other functions
  };
}
```

## Chainlink Protocol Integration

### Price Feed Oracle

The `PasifikaPriceFeed` contract integrates Chainlink's decentralized price oracles to provide reliable market data for token pricing. It features:

- Dynamic token price feed configuration for any ERC-20 token
- Direct USD conversions for token amounts using Chainlink's 8-decimal precision
- Dedicated ETH/USD price feed for gas estimations and native token swaps
- Owner-controlled updates for price feed sources

#### Decimal Handling and Arithmetic Safety

A key implementation detail in the price feed integration is proper decimal scaling between tokens (typically 18 decimals) and Chainlink price feeds (typically 8 decimals):

- **Token → USD conversion:** We scale down token amounts by dividing by 10^10 before multiplication with price to prevent arithmetic overflow
- **USD → Token conversion:** We scale up USD amounts by multiplying by 10^10 and then divide by price
- **Validation:** All price values are validated to be positive before calculations

This approach ensures safe arithmetic operations even with large token amounts while maintaining precise conversions between different decimal representations.

### Fiat Payment Bridge & Multi-Processor Integration

The Pasifika payment system consists of two key contracts:

- **PasifikaFiatBridge**: Manages fiat payment processing with multi-processor support (Circle and Stripe)
- **PasifikaPaymentGateway**: Handles on-chain USDC transactions and fees

#### Key Features

- **Multi-Processor Support**: Seamless integration with multiple payment processors (Circle and Stripe) with processor-specific job IDs for Chainlink oracle requests
- **Chainlink Oracle Integration**: Off-chain payment verification through Chainlink oracles
- **Secure Payment Flow**:
  1. Record pending fiat payment with payment processor reference code
  2. Verify payment status through Chainlink oracle
  3. Process verified payments through the payment gateway
- **Fee Management**: Configurable fee structure with treasury collection
- **Currency Support**: Multiple fiat currencies (FJD, USD, NZD) with automatic conversion rates

#### Example React Hook Integration

```typescript
// /home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/lib/hooks/useFiatBridge.ts

import { useWriteContract, useReadContract } from 'wagmi';
import PasifikaFiatBridgeInfo from '../deployed_contracts/PasifikaFiatBridge.json';
import PasifikaFiatBridgeABI from '../deployed_contracts/PasifikaFiatBridge_ABI.json';

export function useFiatBridge() {
  const { writeContract } = useWriteContract();
  
  // Record a pending fiat payment
  const recordPayment = async (recipient, amountUSDC, currency, paymentId, referenceCode, processor) => {
    return writeContract({
      address: PasifikaFiatBridgeInfo.address as `0x${string}`,
      abi: PasifikaFiatBridgeABI as any,
      functionName: 'recordPendingFiatPayment',
      args: [recipient, amountUSDC, currency, paymentId, referenceCode, processor],
    });
  };
  
  // Verify a payment with a specific processor
  const verifyPayment = async (pendingPaymentId) => {
    return writeContract({
      address: PasifikaFiatBridgeInfo.address as `0x${string}`,
      abi: PasifikaFiatBridgeABI as any,
      functionName: 'verifyPayment',
      args: [pendingPaymentId],
    });
  };
  
  return {
    recordPayment,
    verifyPayment,
    // other functions
  };
}
```

### Cross-Chain Interoperability

The `PasifikaCrossChainBridge` contract utilizes Chainlink's CCIP to enable secure cross-chain functionality:

- Support for Arbitrum, RootStock, and Linea networks with dynamic chain selector configuration
- Cross-chain messaging for protocol governance and updates
- Token transfers across supported networks with automatic fee handling
- LINK token management for paying CCIP fees

Example usage for sending tokens across chains:

```typescript
// /home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/lib/hooks/useCrossChainBridge.ts

import { useWriteContract } from 'wagmi';
import PasifikaBridgeInfo from '../deployed_contracts/PasifikaCrossChainBridge.json';
import PasifikaBridgeABI from '../deployed_contracts/PasifikaCrossChainBridge_ABI.json';

export function useCrossChainBridge() {
  const { writeContract } = useWriteContract();
  
  const sendTokensCrossChain = async (destinationChain, receiverAddress, tokenAddress, amount) => {
    return writeContract({
      address: PasifikaBridgeInfo.address as `0x${string}`,
      abi: PasifikaBridgeABI as any,
      functionName: 'sendTokens',
      args: [destinationChain, receiverAddress, tokenAddress, amount],
    });
  };
  
  return {
    sendTokensCrossChain,
    // other bridge functions
  };
}
```
```

