// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPasifikaExchange
 * @dev Interface for the Pasifika Exchange on Arbitrum
 * @notice This exchange facilitates trading for Pacific Island communities
 */
interface IPasifikaExchange {
    /**
     * @dev Event emitted when a trade is executed
     */
    event TradeExecuted(
        address indexed buyer,
        address indexed seller,
        address indexed tokenAddress,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 timestamp
    );

    /**
     * @dev Event emitted when liquidity is added to the exchange
     */
    event LiquidityAdded(
        address indexed provider,
        address indexed tokenAddress,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 timestamp
    );

    /**
     * @dev Event emitted when liquidity is removed from the exchange
     */
    event LiquidityRemoved(
        address indexed provider,
        address indexed tokenAddress,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 timestamp
    );

    /**
     * @dev Creates a new token pair for trading
     * @param tokenAddress Address of the token to be paired with ETH
     * @param initialTokenAmount Initial amount of tokens for liquidity
     */
    function createPair(address tokenAddress, uint256 initialTokenAmount) external payable;

    /**
     * @dev Adds liquidity to an existing token pair
     * @param tokenAddress Address of the token in the pair
     * @param tokenAmount Amount of tokens to add as liquidity
     */
    function addLiquidity(address tokenAddress, uint256 tokenAmount) external payable;

    /**
     * @dev Removes liquidity from a token pair
     * @param tokenAddress Address of the token in the pair
     * @param liquidityAmount Amount of liquidity to remove
     */
    function removeLiquidity(address tokenAddress, uint256 liquidityAmount) external;

    /**
     * @dev Swaps ETH for tokens
     * @param tokenAddress Address of the token to receive
     * @param minTokens Minimum amount of tokens to receive
     */
    function swapETHForTokens(address tokenAddress, uint256 minTokens) external payable;

    /**
     * @dev Swaps tokens for ETH
     * @param tokenAddress Address of the token to swap
     * @param tokenAmount Amount of tokens to swap
     * @param minETH Minimum amount of ETH to receive
     */
    function swapTokensForETH(address tokenAddress, uint256 tokenAmount, uint256 minETH) external;

    /**
     * @dev Gets the current exchange rate for a token pair
     * @param tokenAddress Address of the token in the pair
     * @return The current exchange rate (token/ETH)
     */
    function getExchangeRate(address tokenAddress) external view returns (uint256);

    /**
     * @dev Gets the current liquidity for a token pair
     * @param tokenAddress Address of the token in the pair
     * @return tokenReserve The current token reserve
     * @return ethReserve The current ETH reserve
     */
    function getLiquidity(address tokenAddress) external view returns (uint256 tokenReserve, uint256 ethReserve);

    /**
     * @dev Gets the amount of tokens that would be received for a given ETH amount
     * @param tokenAddress Address of the token to receive
     * @param ethAmount Amount of ETH to swap
     * @return The amount of tokens that would be received
     */
    function getTokensOutForETH(address tokenAddress, uint256 ethAmount) external view returns (uint256);

    /**
     * @dev Gets the amount of ETH that would be received for a given token amount
     * @param tokenAddress Address of the token to swap
     * @param tokenAmount Amount of tokens to swap
     * @return The amount of ETH that would be received
     */
    function getETHOutForTokens(address tokenAddress, uint256 tokenAmount) external view returns (uint256);
}
