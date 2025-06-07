// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

// Minimal mock with only the functionality we need
interface IMinimalAggregator {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

contract MinimalMockAggregator is IMinimalAggregator {
    int256 public price;
    uint8 public decimalPlaces;
    
    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimalPlaces = _decimals;
    }
    
    function decimals() external view override returns (uint8) {
        return decimalPlaces;
    }
    
    function latestRoundData() external view override returns (
        uint80, int256, uint256, uint256, uint80
    ) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
}

contract MinimalPriceFeedTest is Test {
    MinimalMockAggregator public mockAggregator;
    
    function setUp() public {
        // Create a mock with a very small price to avoid overflow
        mockAggregator = new MinimalMockAggregator(100, 8); // $0.000001 with 8 decimals
        (,int256 price,,,) = mockAggregator.latestRoundData();
        console.log("Mock price feed created with price:", uint256(price));
        console.log("Decimals:", mockAggregator.decimals());
    }
    
    function testGetPrice() public {
        // Get price data
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
            mockAggregator.latestRoundData();
            
        console.log("Retrieved price:", uint256(price));
        assertEq(price, 100);
    }
    
    function testSimpleTokenToUSD() public {
        // Basic price calculation
        uint256 tokenAmount = 1 * 10**18; // 1 token with 18 decimals
        
        (,int256 price,,,) = mockAggregator.latestRoundData();
        uint8 decimals = mockAggregator.decimals();
        
        console.log("Starting values:");
        console.log("Token amount:", tokenAmount);
        console.log("Price:", uint256(price));
        console.log("Decimals:", decimals);
        
        // First reduce token amount (18 decimals) by dividing by 10^10
        uint256 scaledTokenAmount = tokenAmount / 10**10;
        console.log("Scaled token amount:", scaledTokenAmount);
        
        // Calculate USD value (should be safe with these smaller numbers)
        uint256 usdAmount = scaledTokenAmount * uint256(price) / 10**decimals;
        console.log("USD amount:", usdAmount);
        
        // Should be 1 * 0.000001 = 0.000001 (100 with 8 decimals)
        assertEq(usdAmount, 100);
    }
}
