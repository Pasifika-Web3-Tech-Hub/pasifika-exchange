// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PasifikaExchange} from "../src/exchange/PasifikaExchange.sol";
import {PasifikaPriceFeed} from "../src/oracles/PasifikaPriceFeed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PasifikaExchangeTest is Test {
    PasifikaExchange public exchange;
    PasifikaPriceFeed public priceFeed;
    MockToken public usdcToken;
    MockToken public tonganPaangaToken;
    
    address public owner;
    address public user1;
    address public user2;
    
    // ETH/USD Chainlink price feed mock address
    address public constant ETH_USD_FEED = address(0x1);
    
    function setUp() public {
        // Set up accounts
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        vm.startPrank(owner);
        
        // Deploy price feed
        priceFeed = new PasifikaPriceFeed(ETH_USD_FEED);
        
        // Deploy exchange
        exchange = new PasifikaExchange(address(priceFeed));
        
        // Deploy mock tokens
        usdcToken = new MockToken("USD Coin", "USDC");
        tonganPaangaToken = new MockToken("Tongan Pa'anga", "TOP");
        
        // Transfer tokens to users
        usdcToken.transfer(user1, 100_000 * 10**18);
        usdcToken.transfer(user2, 100_000 * 10**18);
        tonganPaangaToken.transfer(user1, 100_000 * 10**18);
        tonganPaangaToken.transfer(user2, 100_000 * 10**18);
        
        vm.stopPrank();
        
        // Give ETH to test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }
    
    function testCreatePair() public {
        vm.startPrank(user1);
        
        // Approve tokens
        usdcToken.approve(address(exchange), 10_000 * 10**18);
        
        // Create pair
        exchange.createPair{value: 5 ether}(address(usdcToken), 10_000 * 10**18);
        
        // Check liquidity
        (uint256 tokenReserve, uint256 ethReserve) = exchange.getLiquidity(address(usdcToken));
        assertEq(tokenReserve, 10_000 * 10**18);
        assertEq(ethReserve, 5 ether);
        
        vm.stopPrank();
    }
    
    function testAddLiquidity() public {
        // First create pair
        vm.startPrank(user1);
        usdcToken.approve(address(exchange), 10_000 * 10**18);
        exchange.createPair{value: 5 ether}(address(usdcToken), 10_000 * 10**18);
        vm.stopPrank();
        
        // User2 adds liquidity
        vm.startPrank(user2);
        usdcToken.approve(address(exchange), 2_000 * 10**18);
        exchange.addLiquidity{value: 1 ether}(address(usdcToken), 2_000 * 10**18);
        vm.stopPrank();
        
        // Check updated liquidity
        (uint256 tokenReserve, uint256 ethReserve) = exchange.getLiquidity(address(usdcToken));
        assertEq(tokenReserve, 12_000 * 10**18);
        assertEq(ethReserve, 6 ether);
    }
    
    function testSwapETHForTokens() public {
        // First create pair
        vm.startPrank(user1);
        usdcToken.approve(address(exchange), 10_000 * 10**18);
        exchange.createPair{value: 5 ether}(address(usdcToken), 10_000 * 10**18);
        vm.stopPrank();
        
        // User2 swaps ETH for tokens
        uint256 user2InitialBalance = usdcToken.balanceOf(user2);
        
        vm.startPrank(user2);
        exchange.swapETHForTokens{value: 0.1 ether}(address(usdcToken), 100 * 10**18);
        vm.stopPrank();
        
        // Check user2 received tokens
        uint256 user2FinalBalance = usdcToken.balanceOf(user2);
        assert(user2FinalBalance > user2InitialBalance);
        
        // Check exchange reserves
        (uint256 tokenReserve, uint256 ethReserve) = exchange.getLiquidity(address(usdcToken));
        assertEq(ethReserve, 5.1 ether);
        assert(tokenReserve < 10_000 * 10**18);
    }
    
    function testSwapTokensForETH() public {
        // First create pair
        vm.startPrank(user1);
        usdcToken.approve(address(exchange), 10_000 * 10**18);
        exchange.createPair{value: 5 ether}(address(usdcToken), 10_000 * 10**18);
        vm.stopPrank();
        
        // User2 swaps tokens for ETH
        uint256 user2InitialEthBalance = address(user2).balance;
        
        vm.startPrank(user2);
        usdcToken.approve(address(exchange), 200 * 10**18);
        exchange.swapTokensForETH(address(usdcToken), 200 * 10**18, 0.05 ether);
        vm.stopPrank();
        
        // Check user2 received ETH
        uint256 user2FinalEthBalance = address(user2).balance;
        assert(user2FinalEthBalance > user2InitialEthBalance);
        
        // Check exchange reserves
        (uint256 tokenReserve, uint256 ethReserve) = exchange.getLiquidity(address(usdcToken));
        assert(tokenReserve > 10_000 * 10**18);
        assert(ethReserve < 5 ether);
    }
    
    function testRemoveLiquidity() public {
        // First create pair
        vm.startPrank(user1);
        usdcToken.approve(address(exchange), 10_000 * 10**18);
        exchange.createPair{value: 5 ether}(address(usdcToken), 10_000 * 10**18);
        
        // Get initial balances
        uint256 initialTokenBalance = usdcToken.balanceOf(user1);
        uint256 initialEthBalance = address(user1).balance;
        
        // Remove half of the liquidity
        exchange.removeLiquidity(address(usdcToken), 5_000 * 10**18);
        
        // Check user1 received tokens and ETH
        uint256 finalTokenBalance = usdcToken.balanceOf(user1);
        uint256 finalEthBalance = address(user1).balance;
        
        assert(finalTokenBalance > initialTokenBalance);
        assert(finalEthBalance > initialEthBalance);
        
        // Check exchange reserves
        (uint256 tokenReserve, uint256 ethReserve) = exchange.getLiquidity(address(usdcToken));
        assertEq(tokenReserve, 5_000 * 10**18);
        assertEq(ethReserve, 2.5 ether);
        
        vm.stopPrank();
    }
}
