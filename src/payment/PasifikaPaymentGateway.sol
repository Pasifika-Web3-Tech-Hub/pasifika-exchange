// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PasifikaPaymentGateway
 * @dev Handles payment processing for the Pasifika Exchange with multi-tier fee structure
 * @notice Cross-chain compatible with Arbitrum, RootStock, and Linea networks
 */
contract PasifikaPaymentGateway is Ownable, ReentrancyGuard {
    // Fee tiers (in basis points, 100 = 1%)
    uint16 public guestFee = 100; // 1.00%
    uint16 public memberFee = 50; // 0.50%
    uint16 public nodeOperatorFee = 25; // 0.25%

    // Treasury address to collect fees
    address public treasuryAddress;

    // Mapping to store user membership tiers
    mapping(address => uint8) public userTiers; // 0=guest, 1=member, 2=node operator

    // Payment receipt structure
    struct Receipt {
        uint256 paymentId;
        address payer;
        address paymentToken; // address(0) for native token
        uint256 amount;
        uint256 feeAmount;
        uint256 timestamp;
        string referenceCode;
        bool completed;
        string networkName; // "Arbitrum", "RootStock", or "Linea"
    }

    // Storage for payment receipts
    mapping(uint256 => Receipt) public receipts;
    uint256 public nextPaymentId = 1;

    // Cross-chain identifiers
    string public currentNetwork;

    // Events
    event PaymentProcessed(
        uint256 indexed paymentId,
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 fee,
        string referenceCode,
        string network
    );

    event MembershipTierUpdated(address indexed user, uint8 tier);

    /**
     * @dev Constructor sets the treasury address and network name
     * @param _treasuryAddress The address to receive transaction fees
     * @param _networkName The blockchain network name (Arbitrum, RootStock, or Linea)
     */
    constructor(address _treasuryAddress, string memory _networkName) Ownable(msg.sender) {
        require(_treasuryAddress != address(0), "Treasury address cannot be zero");
        treasuryAddress = _treasuryAddress;
        currentNetwork = _networkName;
    }

    /**
     * @dev Process a payment using the native token (ETH/RBTC)
     * @param recipient The recipient of the payment
     * @param referenceCode Optional reference code for the payment
     * @return paymentId The ID of the processed payment
     */
    function processNativePayment(address recipient, string calldata referenceCode)
        external
        payable
        nonReentrant
        returns (uint256)
    {
        require(msg.value > 0, "Payment amount must be greater than 0");
        require(recipient != address(0), "Recipient cannot be zero address");

        // Calculate fee based on user tier
        uint16 feeRate = getFeeRateForUser(msg.sender);
        uint256 feeAmount = (msg.value * feeRate) / 10000;
        uint256 recipientAmount = msg.value - feeAmount;

        // Create receipt
        uint256 paymentId = nextPaymentId++;
        receipts[paymentId] = Receipt({
            paymentId: paymentId,
            payer: msg.sender,
            paymentToken: address(0),
            amount: msg.value,
            feeAmount: feeAmount,
            timestamp: block.timestamp,
            referenceCode: referenceCode,
            completed: true,
            networkName: currentNetwork
        });

        // Transfer funds
        if (feeAmount > 0) {
            (bool feeSuccess,) = treasuryAddress.call{value: feeAmount}("");
            require(feeSuccess, "Fee transfer failed");
        }

        (bool recipientSuccess,) = recipient.call{value: recipientAmount}("");
        require(recipientSuccess, "Recipient transfer failed");

        // Emit event
        emit PaymentProcessed(
            paymentId, msg.sender, recipient, address(0), msg.value, feeAmount, referenceCode, currentNetwork
        );

        return paymentId;
    }

    /**
     * @dev Process a payment using an ERC20 token
     * @param token The ERC20 token to use for payment
     * @param recipient The recipient of the payment
     * @param amount The amount of tokens to pay
     * @param referenceCode Optional reference code for the payment
     * @return paymentId The ID of the processed payment
     */
    function processTokenPayment(address token, address recipient, uint256 amount, string calldata referenceCode)
        external
        nonReentrant
        returns (uint256)
    {
        require(amount > 0, "Payment amount must be greater than 0");
        require(token != address(0), "Token address cannot be zero");
        require(recipient != address(0), "Recipient cannot be zero address");

        IERC20 tokenContract = IERC20(token);

        // Calculate fee based on user tier
        uint16 feeRate = getFeeRateForUser(msg.sender);
        uint256 feeAmount = (amount * feeRate) / 10000;
        uint256 recipientAmount = amount - feeAmount;

        // Create receipt
        uint256 paymentId = nextPaymentId++;
        receipts[paymentId] = Receipt({
            paymentId: paymentId,
            payer: msg.sender,
            paymentToken: token,
            amount: amount,
            feeAmount: feeAmount,
            timestamp: block.timestamp,
            referenceCode: referenceCode,
            completed: true,
            networkName: currentNetwork
        });

        // Transfer tokens from sender to this contract
        require(tokenContract.transferFrom(msg.sender, address(this), amount), "Token transfer from sender failed");

        // Transfer fee to treasury
        if (feeAmount > 0) {
            require(tokenContract.transfer(treasuryAddress, feeAmount), "Fee transfer failed");
        }

        // Transfer remaining amount to recipient
        require(tokenContract.transfer(recipient, recipientAmount), "Recipient transfer failed");

        // Emit event
        emit PaymentProcessed(paymentId, msg.sender, recipient, token, amount, feeAmount, referenceCode, currentNetwork);

        return paymentId;
    }

    /**
     * @dev Get the fee rate for a specific user based on their tier
     * @param user The user's address
     * @return The fee rate in basis points (100 = 1%)
     */
    function getFeeRateForUser(address user) public view returns (uint16) {
        uint8 tier = userTiers[user];

        if (tier == 2) {
            return nodeOperatorFee;
        } else if (tier == 1) {
            return memberFee;
        } else {
            return guestFee;
        }
    }

    /**
     * @dev Update a user's membership tier
     * @param user The user's address
     * @param tier The new tier (0=guest, 1=member, 2=node operator)
     */
    function updateUserTier(address user, uint8 tier) external onlyOwner {
        require(tier <= 2, "Invalid tier");
        userTiers[user] = tier;

        emit MembershipTierUpdated(user, tier);
    }

    /**
     * @dev Update the treasury address
     * @param newTreasuryAddress The new treasury address
     */
    function updateTreasuryAddress(address newTreasuryAddress) external onlyOwner {
        require(newTreasuryAddress != address(0), "New treasury address cannot be zero");
        treasuryAddress = newTreasuryAddress;
    }

    /**
     * @dev Update fee rates
     * @param newGuestFee New guest fee rate (in basis points, 100 = 1%)
     * @param newMemberFee New member fee rate (in basis points)
     * @param newNodeOperatorFee New node operator fee rate (in basis points)
     */
    function updateFeeRates(uint16 newGuestFee, uint16 newMemberFee, uint16 newNodeOperatorFee) external onlyOwner {
        require(newGuestFee >= newMemberFee, "Guest fee must be >= member fee");
        require(newMemberFee >= newNodeOperatorFee, "Member fee must be >= node operator fee");

        guestFee = newGuestFee;
        memberFee = newMemberFee;
        nodeOperatorFee = newNodeOperatorFee;
    }

    /**
     * @dev Get payment receipt details
     * @param paymentId The ID of the payment
     * @return The payment receipt details
     */
    function getReceipt(uint256 paymentId) external view returns (Receipt memory) {
        require(paymentId < nextPaymentId, "Invalid payment ID");
        return receipts[paymentId];
    }

    /**
     * @dev Update the network name (for cross-chain deployments)
     * @param _networkName The new network name
     */
    function updateNetworkName(string memory _networkName) external onlyOwner {
        currentNetwork = _networkName;
    }

    /**
     * @dev Get all receipts for a specific user
     * @param user The user's address
     * @param startId The starting payment ID to search from
     * @param maxResults The maximum number of results to return
     * @return An array of payment receipt IDs belonging to the user
     */
    function getUserReceiptIds(address user, uint256 startId, uint256 maxResults)
        external
        view
        returns (uint256[] memory)
    {
        uint256 count = 0;

        // First pass: count matching receipts
        for (uint256 i = startId; i < nextPaymentId && count < maxResults; i++) {
            if (receipts[i].payer == user) {
                count++;
            }
        }

        // Allocate array of the right size
        uint256[] memory userReceiptIds = new uint256[](count);

        // Second pass: populate array
        count = 0;
        for (uint256 i = startId; i < nextPaymentId && count < maxResults; i++) {
            if (receipts[i].payer == user) {
                userReceiptIds[count] = i;
                count++;
            }
        }

        return userReceiptIds;
    }
}
