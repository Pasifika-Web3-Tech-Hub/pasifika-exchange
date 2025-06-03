// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PasifikaCrossChainBridge
 * @dev Implements cross-chain functionality using Chainlink CCIP
 * @notice Enables messaging and token transfers between Arbitrum, RootStock, and Linea
 */
contract PasifikaCrossChainBridge is Ownable {
    // Supported chains with their chain selectors
    enum SupportedChains {
        Arbitrum,    // Index 0
        RootStock,   // Index 1
        Linea        // Index 2
    }
    
    // Mapping to store chain selectors for each supported chain
    mapping(SupportedChains => uint64) public chainSelectors;
    
    // Router addresses for each supported chain
    mapping(SupportedChains => address) public ccipRouters;
    
    // Custom error messages
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error DestinationChainNotSupported(uint64 destinationChainSelector);
    error InvalidReceiverAddress();
    
    // Events
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        bytes message,
        address feeToken,
        uint256 fees
    );
    
    event TokenTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 amount,
        address feeToken,
        uint256 fees
    );
    
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        bytes message
    );
    
    event TokenReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        address token,
        uint256 amount
    );
    
    event ChainAdded(
        SupportedChains indexed chainIndex,
        uint64 chainSelector,
        address routerAddress
    );
    
    // LINK token address on this chain
    address public linkToken;
    
    /**
     * @dev Constructor sets the owner, link token, and chain configurations
     * @param _linkToken Address of the LINK token on this chain
     */
    constructor(address _linkToken) Ownable(msg.sender) {
        linkToken = _linkToken;
        
        // Initialize chain selectors (actual values from Chainlink docs)
        // Arbitrum Sepolia Testnet
        chainSelectors[SupportedChains.Arbitrum] = 0x6900aee69a5a8a14;
        // RootStock Testnet
        chainSelectors[SupportedChains.RootStock] = 0x11e532e2fe718546;
        // Linea Testnet 
        chainSelectors[SupportedChains.Linea] = 0x3ff21c0819444dd4;
        
        // Initialize router addresses (these are testnet addresses and should be updated for mainnet)
        ccipRouters[SupportedChains.Arbitrum] = 0x761faC4c0F02126fD28BE4FDB6623fD2bB2D9b11;
        ccipRouters[SupportedChains.RootStock] = 0x9f3Cf87af6f47C0a26C1Ff0BAf3a4CFba2596886;
        ccipRouters[SupportedChains.Linea] = 0x3c3D92629A0720108Eff808A0167FB99BE9D9829;
    }
    
    /**
     * @dev Updates a chain's configuration
     * @param chain The chain to update
     * @param chainSelector New chain selector
     * @param routerAddress New router address
     */
    function updateChainConfig(
        SupportedChains chain,
        uint64 chainSelector,
        address routerAddress
    ) external onlyOwner {
        chainSelectors[chain] = chainSelector;
        ccipRouters[chain] = routerAddress;
        
        emit ChainAdded(chain, chainSelector, routerAddress);
    }
    
    /**
     * @dev Gets the router client for a specific chain
     * @param chain The chain to get the router for
     * @return The router client
     */
    function getRouter(SupportedChains chain) internal view returns (IRouterClient) {
        return IRouterClient(ccipRouters[chain]);
    }
    
    /**
     * @dev Sends a cross-chain message
     * @param destinationChain The destination chain
     * @param receiver The receiver address on the destination chain
     * @param message The message to send
     * @return messageId The ID of the sent message
     */
    function sendMessage(
        SupportedChains destinationChain,
        address receiver,
        bytes memory message
    ) external returns (bytes32 messageId) {
        uint64 destinationChainSelector = chainSelectors[destinationChain];
        
        if (destinationChainSelector == 0) {
            revert DestinationChainNotSupported(destinationChainSelector);
        }
        
        if (receiver == address(0)) {
            revert InvalidReceiverAddress();
        }
        
        // Create EVM2AnyMessage struct
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: message,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false})
            ),
            feeToken: linkToken
        });
        
        // Get the fee required for sending the message
        IRouterClient router = getRouter(destinationChain);
        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);
        
        // Check if the contract has enough LINK balance
        if (IERC20(linkToken).balanceOf(address(this)) < fees) {
            revert NotEnoughBalance(IERC20(linkToken).balanceOf(address(this)), fees);
        }
        
        // Approve the router to spend LINK tokens
        IERC20(linkToken).approve(address(router), fees);
        
        // Send the message through the router and get the message ID
        messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);
        
        emit MessageSent(
            messageId,
            destinationChainSelector,
            receiver,
            message,
            linkToken,
            fees
        );
        
        return messageId;
    }
    
    /**
     * @dev Sends tokens cross-chain
     * @param destinationChain The destination chain
     * @param receiver The receiver address on the destination chain
     * @param token The token to send
     * @param amount The amount of tokens to send
     * @return messageId The ID of the sent message
     */
    function sendTokens(
        SupportedChains destinationChain,
        address receiver,
        address token,
        uint256 amount
    ) external returns (bytes32 messageId) {
        uint64 destinationChainSelector = chainSelectors[destinationChain];
        
        if (destinationChainSelector == 0) {
            revert DestinationChainNotSupported(destinationChainSelector);
        }
        
        if (receiver == address(0)) {
            revert InvalidReceiverAddress();
        }
        
        // Transfer tokens from sender to this contract
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        // Approve the router to spend tokens
        IERC20(token).approve(address(getRouter(destinationChain)), amount);
        
        // Create token amount array
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: token,
            amount: amount
        });
        
        // Create EVM2AnyMessage struct
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "", // No message data
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false})
            ),
            feeToken: linkToken
        });
        
        // Get the fee required for sending the tokens
        IRouterClient router = getRouter(destinationChain);
        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);
        
        // Check if the contract has enough LINK balance
        if (IERC20(linkToken).balanceOf(address(this)) < fees) {
            revert NotEnoughBalance(IERC20(linkToken).balanceOf(address(this)), fees);
        }
        
        // Approve the router to spend LINK tokens
        IERC20(linkToken).approve(address(router), fees);
        
        // Send the tokens through the router and get the message ID
        messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);
        
        emit TokenTransferred(
            messageId,
            destinationChainSelector,
            receiver,
            token,
            amount,
            linkToken,
            fees
        );
        
        return messageId;
    }
    
    /**
     * @dev Handles received messages from CCIP
     * @param message The received message
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal {
        bytes32 messageId = message.messageId;
        uint64 sourceChainSelector = message.sourceChainSelector;
        address sender = abi.decode(message.sender, (address));
        
        // Handle received tokens if any
        if (message.tokenAmounts.length > 0) {
            for (uint256 i = 0; i < message.tokenAmounts.length; i++) {
                Client.EVMTokenAmount memory tokenAmount = message.tokenAmounts[i];
                emit TokenReceived(
                    messageId,
                    sourceChainSelector,
                    sender,
                    tokenAmount.token,
                    tokenAmount.amount
                );
            }
        }
        
        // Handle received message if any
        if (message.data.length > 0) {
            emit MessageReceived(
                messageId,
                sourceChainSelector,
                sender,
                message.data
            );
        }
    }
    
    /**
     * @dev Deposits LINK tokens to the contract for paying CCIP fees
     * @param amount The amount of LINK to deposit
     */
    function depositLINK(uint256 amount) external {
        IERC20(linkToken).transferFrom(msg.sender, address(this), amount);
    }
    
    /**
     * @dev Withdraws LINK tokens from the contract
     * @param amount The amount of LINK to withdraw
     */
    function withdrawLINK(uint256 amount) external onlyOwner {
        if (IERC20(linkToken).balanceOf(address(this)) < amount) {
            revert NotEnoughBalance(IERC20(linkToken).balanceOf(address(this)), amount);
        }
        
        IERC20(linkToken).transfer(owner(), amount);
    }
    
    /**
     * @dev Withdraws tokens from the contract
     * @param token The token to withdraw
     */
    function withdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) {
            revert NothingToWithdraw();
        }
        
        IERC20(token).transfer(owner(), balance);
    }
    
    /**
     * @dev Withdraws ETH from the contract
     */
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            revert NothingToWithdraw();
        }
        
        (bool success, ) = owner().call{value: balance}("");
        if (!success) {
            revert FailedToWithdrawEth(owner(), owner(), balance);
        }
    }
    
    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
}
