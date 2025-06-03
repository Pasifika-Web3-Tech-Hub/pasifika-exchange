# Pasifika Exchange

**Pasifika Exchange is a cross-chain decentralized exchange platform designed specifically for Pacific Island communities with initial deployment on Arbitrum.**

## Overview

This project implements a decentralized exchange (DEX) to provide essential trading infrastructure for the Pasifika Web3 Tech Hub. Initially built on Arbitrum to take advantage of its low fees and high throughput, the exchange is designed with cross-chain interoperability in mind and optimized for the needs of Pacific Island users.

### Key Components

-   **PasifikaExchange**: An AMM-style (Automated Market Maker) DEX that allows cross-chain trading between tokens on multiple EVM Compatible networks
-   **PasifikaPriceFeed**: Chainlink oracle integration for reliable cross-chain price data
-   **Multi-Network Support**: Initially deployed on Arbitrum with planned interoperability for Linea and RootStock

### Technology Stack

The Pasifika Exchange is built with:

-   **Foundry**: Smart contract development framework
-   **Solidity**: Smart contract programming language
-   **Chainlink**: Price feeds and oracles
-   **OpenZeppelin**: Secure contract implementations
-   **EVM Compatible Networks**: Multiple Layer 2 and sidechain solutions
-   **Cross-Chain Bridges**: For interoperability between networks

## Frontend Integration

The deployment script automatically copies contract addresses and ABIs to the Pasifika Web3 frontend at:
```
/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts/
```

### Contract Files Generated

1. `PasifikaPriceFeed.json` - Contains address and metadata
2. `PasifikaExchange.json` - Contains address and metadata
3. `PasifikaPriceFeed_ABI.json` - Full contract ABI
4. `PasifikaExchange_ABI.json` - Full contract ABI

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

