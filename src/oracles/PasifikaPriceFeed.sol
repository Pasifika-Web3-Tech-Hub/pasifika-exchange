// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPasifikaPriceFeed.sol";

/**
 * @title PasifikaPriceFeed
 * @dev Implementation of the price feed oracle for Pasifika Exchange
 * @notice Uses Chainlink price feeds to get real-time market data
 */
contract PasifikaPriceFeed is IPasifikaPriceFeed, Ownable {
    // Mapping from token address to price feed address
    mapping(address => address) private priceFeedAddresses;

    // ETH/USD price feed address
    address public ethUsdPriceFeed;

    /**
     * @dev Constructor sets the owner and ETH/USD price feed
     * @param _ethUsdPriceFeed Address of the ETH/USD Chainlink price feed
     */
    constructor(address _ethUsdPriceFeed) Ownable(msg.sender) {
        ethUsdPriceFeed = _ethUsdPriceFeed;
    }

    /**
     * @dev Sets the price feed for a token
     * @param tokenAddress Address of the token
     * @param priceFeedAddress Address of the Chainlink price feed for the token/USD pair
     */
    function setPriceFeed(address tokenAddress, address priceFeedAddress) external onlyOwner {
        priceFeedAddresses[tokenAddress] = priceFeedAddress;
    }

    /**
     * @dev Updates the ETH/USD price feed
     * @param _ethUsdPriceFeed New address for the ETH/USD price feed
     */
    function updateEthUsdPriceFeed(address _ethUsdPriceFeed) external onlyOwner {
        ethUsdPriceFeed = _ethUsdPriceFeed;
    }

    /**
     * @dev Gets the latest price for a token in USD from Chainlink
     * @param tokenAddress Address of the token
     * @return The latest price with 8 decimals
     */
    function getLatestPrice(address tokenAddress) external view override returns (int256) {
        address priceFeedAddress = priceFeedAddresses[tokenAddress];
        require(priceFeedAddress != address(0), "Price feed not found");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid negative price");

        return price;
    }

    /**
     * @dev Gets the latest ETH price in USD from Chainlink
     * @return The latest ETH price with 8 decimals
     */
    function getLatestETHPrice() public view override returns (int256) {
        require(ethUsdPriceFeed != address(0), "ETH price feed not set");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(ethUsdPriceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return price;
    }

    /**
     * @dev Converts an amount of tokens to its USD value
     * @param tokenAddress Address of the token
     * @param amount Amount of tokens to convert
     * @return The USD value with 8 decimals
     */
    function convertTokenToUSD(address tokenAddress, uint256 amount) external view override returns (uint256) {
        address priceFeedAddress = priceFeedAddresses[tokenAddress];
        require(priceFeedAddress != address(0), "Price feed not found");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        uint8 decimals = priceFeed.decimals();

        // Avoid overflow by scaling down token amount (from 18 decimals)
        // by dividing it by 10^10, keeping effectively 8 decimals
        uint256 scaledAmount = amount / 10 ** 10;

        // Now we can safely multiply by price and adjust for decimals
        // Result will be in USD value with the same number of decimals as the price feed (typically 8)
        return (scaledAmount * uint256(price)) / 10 ** decimals;
    }

    /**
     * @dev Converts an amount in USD to its token equivalent
     * @param tokenAddress Address of the token
     * @param usdAmount Amount in USD to convert (with 8 decimals)
     * @return The token amount
     */
    function convertUSDToToken(address tokenAddress, uint256 usdAmount) external view override returns (uint256) {
        address priceFeedAddress = priceFeedAddresses[tokenAddress];
        require(priceFeedAddress != address(0), "Price feed not found");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");

        // For token with 18 decimals from USD amount with 8 decimals (typical for Chainlink)
        // We multiply by 10^10 to get the 18-decimal representation
        // Final result will have 18 decimals (standard for ERC20 tokens)
        return (usdAmount * 10 ** 10) / uint256(price);
    }

    /**
     * @dev Gets the decimals for a price feed
     * @param tokenAddress Address of the token
     * @return The number of decimals
     */
    function getPriceFeedDecimals(address tokenAddress) external view returns (uint8) {
        address priceFeedAddress = priceFeedAddresses[tokenAddress];
        require(priceFeedAddress != address(0), "Price feed not found");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        return priceFeed.decimals();
    }
}
