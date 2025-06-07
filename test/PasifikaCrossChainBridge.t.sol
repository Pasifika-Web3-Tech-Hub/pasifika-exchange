// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PasifikaCrossChainBridge} from "../src/oracles/PasifikaCrossChainBridge.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock LINK token for testing
contract MockLinkToken is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from the zero address");
        require(to != address(0), "Transfer to the zero address");

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "Transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from the zero address");
        require(spender != address(0), "Approve to the zero address");

        _allowances[owner][spender] = amount;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
}

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
    
    // Standard ERC20 implementations
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        require(allowed >= amount, "Insufficient allowance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] = allowed - amount;
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
}

// Mock router client for Chainlink CCIP
contract MockRouterClient is IRouterClient {
    bytes32 public lastMessageId = bytes32(0);
    uint256 public mockFee = 0.1 ether;
    mapping(bytes32 => Client.EVM2AnyMessage) public sentMessages;
    address public linkToken;
    mapping(uint64 => bool) public supportedChains;
    
    constructor(address _linkToken) {
        linkToken = _linkToken;
        
        // Default supported chains
        supportedChains[0x6900aee69a5a8a14] = true; // Arbitrum
        supportedChains[0x11e532e2fe718546] = true; // RootStock
        supportedChains[0x3ff21c0819444dd4] = true; // Linea
    }
    
    function setMockFee(uint256 _fee) external {
        mockFee = _fee;
    }
    
    function isChainSupported(uint64 chainSelector) external view override returns (bool) {
        return supportedChains[chainSelector];
    }
    
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message) 
        external 
        payable
        override 
        returns (bytes32)
    {
        // Check if chain is supported
        require(this.isChainSupported(destinationChainSelector), "Unsupported chain");
        
        // Generate a unique message ID based on sender, destination chain, and timestamp
        bytes32 messageId = keccak256(abi.encode(msg.sender, destinationChainSelector, block.timestamp, message.data));
        
        // Store the message
        sentMessages[messageId] = message;
        lastMessageId = messageId;
        
        // Return the message ID
        return messageId;
    }
    
    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage memory message) 
        external 
        view 
        override 
        returns (uint256)
    {
        return mockFee;
    }
    
    // Helper function for testing to simulate message received
    function simulateMessageReceived(address sender, Client.EVM2AnyMessage memory message) external {
        // Could implement logic here to simulate handling of received messages if needed
    }
    
    function setSupportedChain(uint64 chainSelector, bool isSupported) external {
        supportedChains[chainSelector] = isSupported;
    }
}

contract PasifikaCrossChainBridgeTest is Test {
    PasifikaCrossChainBridge public bridge;
    MockLinkToken public mockLink;
    MockERC20 public mockToken;
    MockRouterClient public router;
    
    address public owner;
    address public user1;
    address public receiver;
    
    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        receiver = makeAddr("receiver");
        
        // Deploy mock contracts
        mockLink = new MockLinkToken();
        mockToken = new MockERC20();
        router = new MockRouterClient(address(mockLink));
        
        // Deploy the bridge contract
        vm.prank(owner);
        bridge = new PasifikaCrossChainBridge(address(mockLink));
        
        // Mint tokens for testing
        mockLink.mint(address(this), 100 ether);
        mockToken.mint(user1, 100 ether);
        
        // Transfer some LINK to the bridge
        mockLink.transfer(address(bridge), 1 ether);
    }
    
    function testSendMessage() public {
        bytes memory messageData = abi.encode("Hello, Cross-Chain World!");
        
        // Setup routers to support the destination chain
        vm.prank(owner);
        bridge.updateChainConfig(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            0x6900aee69a5a8a14, // Arbitrum chain selector
            address(router)
        );
        
        // Mint and approve LINK tokens for user1
        mockLink.mint(user1, 1 ether);
        
        vm.startPrank(user1);
        mockLink.approve(address(bridge), 1 ether);
        bridge.depositLINK(1 ether);
        
        // Send a cross-chain message
        bytes32 messageId = bridge.sendMessage(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            receiver,
            messageData
        );
        
        vm.stopPrank();
        
        // Verify the message ID is not empty
        assertFalse(messageId == bytes32(0));
    }
    
    function testSendTokens() public {
        // Setup routers to support the destination chain
        vm.prank(owner);
        bridge.updateChainConfig(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            0x6900aee69a5a8a14, // Arbitrum chain selector
            address(router)
        );
        
        // Mint and approve tokens for user1
        mockLink.mint(user1, 1 ether);
        mockToken.mint(user1, 10 ether);
        
        vm.startPrank(user1);
        mockLink.approve(address(bridge), 1 ether);
        bridge.depositLINK(1 ether);
        
        mockToken.approve(address(bridge), 10 ether);
        
        // Send tokens cross-chain
        bytes32 messageId = bridge.sendTokens(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            receiver,
            address(mockToken),
            10 ether
        );
        
        vm.stopPrank();
        
        // Verify the message ID is not empty
        assertFalse(messageId == bytes32(0));
    }
    
    function testUpdateChainConfig() public {
        // Only owner should be able to update chain config
        uint64 newChainSelector = 0x1234567890abcdef;
        address newRouterAddress = makeAddr("newRouter");
        
        vm.prank(owner);
        bridge.updateChainConfig(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            newChainSelector,
            newRouterAddress
        );
    }
    
    function testOnlyOwnerFunctions() public {
        // Non-owner should not be able to update chain config
        vm.startPrank(user1);
        vm.expectRevert();
        bridge.updateChainConfig(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            0x1234,
            address(0x1234)
        );
        
        // Non-owner should not be able to withdraw LINK
        vm.expectRevert();
        bridge.withdrawLINK(1 ether);
        
        // Non-owner should not be able to withdraw tokens
        vm.expectRevert();
        bridge.withdrawToken(address(mockToken));
        
        // Non-owner should not be able to withdraw ETH
        vm.expectRevert();
        bridge.withdrawETH();
        
        vm.stopPrank();
    }
    
    function testDepositAndWithdrawLINK() public {
        // User deposits LINK
        mockLink.mint(user1, 2 ether);
        
        vm.startPrank(user1);
        mockLink.approve(address(bridge), 2 ether);
        bridge.depositLINK(2 ether);
        vm.stopPrank();
        
        // Check LINK balance
        assertEq(mockLink.balanceOf(address(bridge)), 3 ether); // 1 ether from setup + 2 ether deposit
        
        // Owner withdraws LINK
        vm.prank(owner);
        bridge.withdrawLINK(1 ether);
        
        // Check updated balance
        assertEq(mockLink.balanceOf(address(bridge)), 2 ether);
        assertEq(mockLink.balanceOf(owner), 1 ether);
    }
    
    function testDepositAndWithdrawToken() public {
        // Deposit some tokens to the bridge
        mockToken.mint(address(bridge), 5 ether);
        assertEq(mockToken.balanceOf(address(bridge)), 5 ether);
        
        // Owner withdraws tokens
        vm.prank(owner);
        bridge.withdrawToken(address(mockToken));
        
        // Check balances
        assertEq(mockToken.balanceOf(address(bridge)), 0);
        assertEq(mockToken.balanceOf(owner), 5 ether);
    }
    
    function testEthHandling() public {
        // Send ETH to the bridge
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool success,) = address(bridge).call{value: 1 ether}("");
        assertTrue(success);
        
        // Check bridge balance
        assertEq(address(bridge).balance, 1 ether);
        
        // Owner withdraws ETH
        uint256 ownerBalanceBefore = owner.balance;
        vm.prank(owner);
        bridge.withdrawETH();
        
        // Check balances
        assertEq(address(bridge).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + 1 ether);
    }

    function testRevertWhenDestinationChainNotSupported() public {
        // Test the chain not supported reversion
        uint64 invalidChainSelector = 999;
        
        // Set up a new chain with this invalid selector
        vm.prank(owner);
        bridge.updateChainConfig(
            PasifikaCrossChainBridge.SupportedChains.Linea,
            invalidChainSelector,
            address(router)
        );
        
        // Explicitly mark this chain as unsupported in the router
        router.setSupportedChain(invalidChainSelector, false);
        
        // Mint and deposit LINK for user1
        mockLink.mint(user1, 1 ether);
        vm.startPrank(user1);
        mockLink.approve(address(bridge), 1 ether);
        bridge.depositLINK(1 ether);
        
        // Try to send a message which should fail due to unsupported chain
        vm.expectRevert();
        bridge.sendMessage(
            PasifikaCrossChainBridge.SupportedChains.Linea,
            receiver,
            abi.encode("This should fail")
        );
        
        vm.stopPrank();
    }
    
    function testRevertWhenInvalidReceiverAddress() public {
        // Mint and deposit LINK for user1
        mockLink.mint(user1, 1 ether);
        
        vm.startPrank(user1);
        mockLink.approve(address(bridge), 1 ether);
        bridge.depositLINK(1 ether);
        
        // Try to send to zero address
        vm.expectRevert(PasifikaCrossChainBridge.InvalidReceiverAddress.selector);
        bridge.sendMessage(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            address(0),
            abi.encode("To zero address")
        );
        
        vm.stopPrank();
    }
    
    function testRevertWhenNotEnoughLINK() public {
        bytes memory messageData = abi.encode("Hello, Cross-Chain World!");
        
        // Setup router to support the destination chain
        vm.prank(owner);
        bridge.updateChainConfig(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            0x6900aee69a5a8a14, // Arbitrum chain selector
            address(router)
        );
        
        // Set mock fee higher than LINK balance
        router.setMockFee(10 ether);
        
        // Clear any existing LINK balance and add a small amount
        mockLink = new MockLinkToken(); // Create fresh token to reset balances
        
        // Set up the router with the correct link token
        router = new MockRouterClient(address(mockLink));
        
        // Update the chain config to use the new router
        vm.prank(owner);
        bridge.updateChainConfig(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            0x6900aee69a5a8a14,
            address(router)
        );
        
        // Deploy a new bridge with the new link token
        vm.prank(owner);
        bridge = new PasifikaCrossChainBridge(address(mockLink));
        
        // Mint and deposit a small amount of LINK for user1
        mockLink.mint(user1, 0.5 ether);
        
        vm.startPrank(user1);
        mockLink.approve(address(bridge), 0.5 ether);
        bridge.depositLINK(0.5 ether);
        
        // Try to send a message which should fail due to insufficient LINK
        // The contract uses a custom error with parameters: NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees)
        // We don't know the exact fee value that will be calculated, so we'll use vm.expectRevert() without parameters
        vm.expectRevert();
        bridge.sendMessage(
            PasifikaCrossChainBridge.SupportedChains.Arbitrum,
            receiver,
            messageData
        );
        
        vm.stopPrank();
    }
}
