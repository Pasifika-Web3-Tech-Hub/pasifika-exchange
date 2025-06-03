// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IPasifikaExchange.sol";
import "../interfaces/IPasifikaPriceFeed.sol";

/**
 * @title PasifikaExchange
 * @dev Main implementation of the Pasifika Exchange for Pacific Island communities
 * @notice This exchange facilitates trading on Arbitrum with reduced fees and better UX
 */
contract PasifikaExchange is IPasifikaExchange, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constant for fee calculation (0.3%)
    uint256 private constant FEE_RATE = 3;
    uint256 private constant FEE_DENOMINATOR = 1000;
    
    // Address of the price feed oracle
    IPasifikaPriceFeed public priceFeed;
    
    // Struct to store pair information
    struct PairInfo {
        uint256 tokenReserve;
        uint256 ethReserve;
        bool exists;
    }
    
    // Mapping from token address to pair information
    mapping(address => PairInfo) public pairs;
    
    // Mapping from token address to liquidity provider to LP token balance
    mapping(address => mapping(address => uint256)) public liquidityTokens;
    
    // Total liquidity for each pair
    mapping(address => uint256) public totalLiquidity;
    
    /**
     * @dev Constructor sets the owner and price feed address
     * @param _priceFeed Address of the price feed oracle
     */
    constructor(address _priceFeed) Ownable(msg.sender) {
        priceFeed = IPasifikaPriceFeed(_priceFeed);
    }
    
    /**
     * @dev Updates the price feed address
     * @param _priceFeed New address for the price feed
     */
    function updatePriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = IPasifikaPriceFeed(_priceFeed);
    }
    
    /**
     * @dev Creates a new token pair for trading
     * @param tokenAddress Address of the token to be paired with ETH
     * @param initialTokenAmount Initial amount of tokens for liquidity
     */
    function createPair(address tokenAddress, uint256 initialTokenAmount) external payable override nonReentrant {
        require(tokenAddress != address(0), "Invalid token address");
        require(!pairs[tokenAddress].exists, "Pair already exists");
        require(initialTokenAmount > 0, "Token amount must be greater than 0");
        require(msg.value > 0, "ETH amount must be greater than 0");
        
        // Transfer tokens from sender to contract
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), initialTokenAmount);
        
        // Create new pair
        pairs[tokenAddress] = PairInfo({
            tokenReserve: initialTokenAmount,
            ethReserve: msg.value,
            exists: true
        });
        
        // Issue liquidity tokens to the provider
        liquidityTokens[tokenAddress][msg.sender] = initialTokenAmount;
        totalLiquidity[tokenAddress] = initialTokenAmount;
        
        emit LiquidityAdded(msg.sender, tokenAddress, initialTokenAmount, msg.value, block.timestamp);
    }
    
    /**
     * @dev Adds liquidity to an existing token pair
     * @param tokenAddress Address of the token in the pair
     * @param tokenAmount Amount of tokens to add as liquidity
     */
    function addLiquidity(address tokenAddress, uint256 tokenAmount) external payable override nonReentrant {
        require(pairs[tokenAddress].exists, "Pair does not exist");
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(msg.value > 0, "ETH amount must be greater than 0");
        
        PairInfo storage pair = pairs[tokenAddress];
        
        // Calculate the required ratio of tokens to ETH
        uint256 ethAmount = (tokenAmount * pair.ethReserve) / pair.tokenReserve;
        uint256 tokenAmountRequired = (msg.value * pair.tokenReserve) / pair.ethReserve;
        
        // Use the minimum amount to maintain ratio
        uint256 ethToAdd;
        uint256 tokensToAdd;
        
        if (msg.value >= ethAmount) {
            ethToAdd = ethAmount;
            tokensToAdd = tokenAmount;
            // Refund excess ETH
            if (msg.value > ethAmount) {
                (bool success, ) = msg.sender.call{value: msg.value - ethAmount}("");
                require(success, "ETH refund failed");
            }
        } else {
            ethToAdd = msg.value;
            tokensToAdd = tokenAmountRequired;
        }
        
        // Transfer tokens from sender to contract
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokensToAdd);
        
        // Calculate liquidity tokens to mint
        uint256 liquidityToMint = (tokensToAdd * totalLiquidity[tokenAddress]) / pair.tokenReserve;
        
        // Update state
        pair.tokenReserve += tokensToAdd;
        pair.ethReserve += ethToAdd;
        liquidityTokens[tokenAddress][msg.sender] += liquidityToMint;
        totalLiquidity[tokenAddress] += liquidityToMint;
        
        emit LiquidityAdded(msg.sender, tokenAddress, tokensToAdd, ethToAdd, block.timestamp);
    }
    
    /**
     * @dev Removes liquidity from a token pair
     * @param tokenAddress Address of the token in the pair
     * @param liquidityAmount Amount of liquidity to remove
     */
    function removeLiquidity(address tokenAddress, uint256 liquidityAmount) external override nonReentrant {
        require(pairs[tokenAddress].exists, "Pair does not exist");
        require(liquidityAmount > 0, "Amount must be greater than 0");
        require(liquidityTokens[tokenAddress][msg.sender] >= liquidityAmount, "Insufficient liquidity tokens");
        
        PairInfo storage pair = pairs[tokenAddress];
        
        // Calculate tokens and ETH to return based on share
        uint256 tokenAmount = (liquidityAmount * pair.tokenReserve) / totalLiquidity[tokenAddress];
        uint256 ethAmount = (liquidityAmount * pair.ethReserve) / totalLiquidity[tokenAddress];
        
        // Update state
        liquidityTokens[tokenAddress][msg.sender] -= liquidityAmount;
        totalLiquidity[tokenAddress] -= liquidityAmount;
        pair.tokenReserve -= tokenAmount;
        pair.ethReserve -= ethAmount;
        
        // Transfer assets back to the user
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        
        emit LiquidityRemoved(msg.sender, tokenAddress, tokenAmount, ethAmount, block.timestamp);
    }
    
    /**
     * @dev Swaps ETH for tokens
     * @param tokenAddress Address of the token to receive
     * @param minTokens Minimum amount of tokens to receive
     */
    function swapETHForTokens(address tokenAddress, uint256 minTokens) external payable override nonReentrant {
        require(pairs[tokenAddress].exists, "Pair does not exist");
        require(msg.value > 0, "ETH amount must be greater than 0");
        
        PairInfo storage pair = pairs[tokenAddress];
        
        // Calculate tokens to receive
        uint256 inputAmount = msg.value;
        uint256 inputWithFee = inputAmount * (FEE_DENOMINATOR - FEE_RATE);
        uint256 numerator = inputWithFee * pair.tokenReserve;
        uint256 denominator = (pair.ethReserve * FEE_DENOMINATOR) + inputWithFee;
        uint256 tokenAmount = numerator / denominator;
        
        require(tokenAmount >= minTokens, "Output amount below minimum");
        
        // Update reserves
        pair.ethReserve += inputAmount;
        pair.tokenReserve -= tokenAmount;
        
        // Transfer tokens to sender
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        
        emit TradeExecuted(msg.sender, address(this), tokenAddress, tokenAmount, msg.value, block.timestamp);
    }
    
    /**
     * @dev Swaps tokens for ETH
     * @param tokenAddress Address of the token to swap
     * @param tokenAmount Amount of tokens to swap
     * @param minETH Minimum amount of ETH to receive
     */
    function swapTokensForETH(address tokenAddress, uint256 tokenAmount, uint256 minETH) external override nonReentrant {
        require(pairs[tokenAddress].exists, "Pair does not exist");
        require(tokenAmount > 0, "Token amount must be greater than 0");
        
        PairInfo storage pair = pairs[tokenAddress];
        
        // Calculate ETH to receive
        uint256 inputWithFee = tokenAmount * (FEE_DENOMINATOR - FEE_RATE);
        uint256 numerator = inputWithFee * pair.ethReserve;
        uint256 denominator = (pair.tokenReserve * FEE_DENOMINATOR) + inputWithFee;
        uint256 ethAmount = numerator / denominator;
        
        require(ethAmount >= minETH, "Output amount below minimum");
        
        // Transfer tokens from sender
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);
        
        // Update reserves
        pair.tokenReserve += tokenAmount;
        pair.ethReserve -= ethAmount;
        
        // Transfer ETH to sender
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        
        emit TradeExecuted(msg.sender, address(this), tokenAddress, tokenAmount, ethAmount, block.timestamp);
    }
    
    /**
     * @dev Gets the current exchange rate for a token pair
     * @param tokenAddress Address of the token in the pair
     * @return The current exchange rate (tokens per ETH)
     */
    function getExchangeRate(address tokenAddress) external view override returns (uint256) {
        require(pairs[tokenAddress].exists, "Pair does not exist");
        
        PairInfo memory pair = pairs[tokenAddress];
        
        // Return tokens per ETH
        return (pair.tokenReserve * 1e18) / pair.ethReserve;
    }
    
    /**
     * @dev Gets the current liquidity for a token pair
     * @param tokenAddress Address of the token in the pair
     * @return tokenReserve The current token reserve
     * @return ethReserve The current ETH reserve
     */
    function getLiquidity(address tokenAddress) external view override returns (uint256 tokenReserve, uint256 ethReserve) {
        require(pairs[tokenAddress].exists, "Pair does not exist");
        
        PairInfo memory pair = pairs[tokenAddress];
        return (pair.tokenReserve, pair.ethReserve);
    }
    
    /**
     * @dev Gets the amount of tokens that would be received for a given ETH amount
     * @param tokenAddress Address of the token to receive
     * @param ethAmount Amount of ETH to swap
     * @return The amount of tokens that would be received
     */
    function getTokensOutForETH(address tokenAddress, uint256 ethAmount) external view override returns (uint256) {
        require(pairs[tokenAddress].exists, "Pair does not exist");
        
        PairInfo memory pair = pairs[tokenAddress];
        
        // Calculate tokens to receive
        uint256 inputWithFee = ethAmount * (FEE_DENOMINATOR - FEE_RATE);
        uint256 numerator = inputWithFee * pair.tokenReserve;
        uint256 denominator = (pair.ethReserve * FEE_DENOMINATOR) + inputWithFee;
        return numerator / denominator;
    }
    
    /**
     * @dev Gets the amount of ETH that would be received for a given token amount
     * @param tokenAddress Address of the token to swap
     * @param tokenAmount Amount of tokens to swap
     * @return The amount of ETH that would be received
     */
    function getETHOutForTokens(address tokenAddress, uint256 tokenAmount) external view override returns (uint256) {
        require(pairs[tokenAddress].exists, "Pair does not exist");
        
        PairInfo memory pair = pairs[tokenAddress];
        
        // Calculate ETH to receive
        uint256 inputWithFee = tokenAmount * (FEE_DENOMINATOR - FEE_RATE);
        uint256 numerator = inputWithFee * pair.ethReserve;
        uint256 denominator = (pair.tokenReserve * FEE_DENOMINATOR) + inputWithFee;
        return numerator / denominator;
    }
}
