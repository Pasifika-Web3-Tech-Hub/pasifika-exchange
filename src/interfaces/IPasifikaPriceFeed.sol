// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPasifikaPriceFeed
 * @dev Interface for the price feed oracle used by Pasifika Exchange
 * @notice This interface handles price data from Chainlink oracles
 */
interface IPasifikaPriceFeed {
    /**
     * @dev Gets the latest price for a token in USD
     * @param tokenAddress Address of the token
     * @return The latest price with 8 decimals
     */
    function getLatestPrice(address tokenAddress) external view returns (int256);

    /**
     * @dev Gets the latest ETH price in USD
     * @return The latest ETH price with 8 decimals
     */
    function getLatestETHPrice() external view returns (int256);

    /**
     * @dev Converts an amount of tokens to its USD value
     * @param tokenAddress Address of the token
     * @param amount Amount of tokens to convert
     * @return The USD value with 8 decimals
     */
    function convertTokenToUSD(address tokenAddress, uint256 amount) external view returns (uint256);

    /**
     * @dev Converts an amount in USD to its token equivalent
     * @param tokenAddress Address of the token
     * @param usdAmount Amount in USD to convert
     * @return The token amount
     */
    function convertUSDToToken(address tokenAddress, uint256 usdAmount) external view returns (uint256);
}
