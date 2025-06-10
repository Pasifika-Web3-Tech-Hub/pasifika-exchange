// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/operatorforwarder/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./PasifikaPaymentGateway.sol";

/**
 * @title PasifikaFiatBridge
 * @dev Bridge between fiat payments and crypto payments using multiple payment processors (Circle, Stripe) and Chainlink oracles
 * @notice Supports major Pacific Island currencies: NZD, FJD, WST, TOP, PGK
 */
contract PasifikaFiatBridge is Ownable, ReentrancyGuard, ChainlinkClient {
    using Chainlink for Chainlink.Request;

    // Payment Gateway reference
    PasifikaPaymentGateway public paymentGateway;

    // USDC token contract
    IERC20 public usdcToken;

    // Chainlink oracle details
    address public oracle;
    bytes32 private circleJobId;
    bytes32 private stripeJobId;
    uint256 private fee;

    // Job selector mapping for different payment processors
    mapping(PaymentProcessor => bytes32) public processorJobIds;

    // Forex price feeds
    mapping(string => AggregatorV3Interface) public forexPriceFeeds;

    // Supported fiat currencies
    string[] public supportedCurrencies;

    // Payment processor types
    enum PaymentProcessor {
        Circle,
        Stripe
    }

    // Pending payments from fiat payment processors
    struct PendingFiatPayment {
        address recipient;
        uint256 amountUSDC;
        string currency;
        string paymentProcessorId; // Circle payment ID or Stripe payment intent ID
        string referenceCode;
        bool processed;
        PaymentProcessor processor; // Which payment processor was used
    }

    // Mapping from Chainlink request ID to pending payment ID
    mapping(bytes32 => uint256) public chainlinkRequests;

    // Pending payments storage
    mapping(uint256 => PendingFiatPayment) public pendingPayments;
    uint256 public nextPendingPaymentId = 1;

    // Fiat payment verification events
    event FiatPaymentInitiated(
        uint256 indexed pendingPaymentId,
        string currency,
        uint256 amountUSDC,
        address recipient,
        string paymentProcessorId,
        PaymentProcessor processor
    );

    event FiatPaymentConfirmed(
        uint256 indexed pendingPaymentId,
        uint256 indexed paymentGatewayId,
        string paymentProcessorId,
        PaymentProcessor processor
    );

    event FiatPaymentFailed(
        uint256 indexed pendingPaymentId, string paymentProcessorId, string reason, PaymentProcessor processor
    );

    /**
     * @dev Constructor initializes the contract with required parameters
     * @param _usdcTokenAddress The address of the USDC token contract
     * @param _paymentGatewayAddress The address of the payment gateway contract
     * @param _chainlinkToken The address of the LINK token
     * @param _oracle The address of the Chainlink oracle
     * @param _circleJobId The job ID for Circle payment verification via Chainlink oracle
     * @param _stripeJobId The job ID for Stripe payment verification via Chainlink oracle
     * @param _linkFee The fee in LINK tokens for Chainlink requests
     */
    constructor(
        address _usdcTokenAddress,
        address _paymentGatewayAddress,
        address _chainlinkToken,
        address _oracle,
        bytes32 _circleJobId,
        bytes32 _stripeJobId,
        uint256 _linkFee,
        address /* _treasuryAddress */ // Commented out unused parameter
    ) Ownable(msg.sender) {
        require(_paymentGatewayAddress != address(0), "Invalid payment gateway address");
        require(_usdcTokenAddress != address(0), "Invalid USDC token address");
        require(_chainlinkToken != address(0), "Invalid LINK token address");
        require(_oracle != address(0), "Invalid oracle address");

        paymentGateway = PasifikaPaymentGateway(_paymentGatewayAddress);
        usdcToken = IERC20(_usdcTokenAddress);

        _setChainlinkToken(_chainlinkToken);
        oracle = _oracle;
        circleJobId = _circleJobId;
        stripeJobId = _stripeJobId;
        fee = _linkFee;

        // Set up job IDs for each payment processor
        processorJobIds[PaymentProcessor.Circle] = _circleJobId;
        processorJobIds[PaymentProcessor.Stripe] = _stripeJobId;
    }

    /**
     * @dev Registers a forex price feed for a specific currency
     * @param currency The currency code (e.g., "NZD", "FJD", "WST")
     * @param priceFeed Address of the Chainlink price feed for this currency/USD pair
     */
    function registerForexPriceFeed(string calldata currency, address priceFeed) external onlyOwner {
        require(priceFeed != address(0), "Invalid price feed address");

        // Check if this is a new currency
        bool isNewCurrency = forexPriceFeeds[currency] == AggregatorV3Interface(address(0));

        // Set the price feed
        forexPriceFeeds[currency] = AggregatorV3Interface(priceFeed);

        // Add to supported currencies if new
        if (isNewCurrency) {
            supportedCurrencies.push(currency);
        }
    }

    /**
     * @dev Records a pending fiat payment from a payment processor
     * @param recipient The recipient of the payment
     * @param amountUSDC The amount in USDC
     * @param currency The currency code (NZD, FJD, etc.)
     * @param paymentProcessorId The payment processor's payment ID/reference
     * @param referenceCode A reference code for the payment
     * @param processor The payment processor type (Circle or Stripe)
     * @return The ID of the pending payment
     */
    function recordPendingFiatPayment(
        address recipient,
        uint256 amountUSDC,
        string calldata currency,
        string calldata paymentProcessorId,
        string calldata referenceCode,
        PaymentProcessor processor
    ) external onlyOwner returns (uint256) {
        require(recipient != address(0), "Invalid recipient address");
        require(amountUSDC > 0, "Amount must be greater than 0");

        uint256 pendingPaymentId = nextPendingPaymentId++;

        pendingPayments[pendingPaymentId] = PendingFiatPayment({
            recipient: recipient,
            amountUSDC: amountUSDC,
            currency: currency,
            paymentProcessorId: paymentProcessorId,
            referenceCode: referenceCode,
            processed: false,
            processor: processor
        });

        emit FiatPaymentInitiated(pendingPaymentId, currency, amountUSDC, recipient, paymentProcessorId, processor);

        return pendingPaymentId;
    }

    /**
     * @dev Requests payment verification from Chainlink oracle
     * @param pendingPaymentId The ID of the pending payment to verify
     */
    function verifyPayment(uint256 pendingPaymentId) public onlyOwner {
        require(pendingPaymentId < nextPendingPaymentId, "Invalid pending payment ID");
        require(!pendingPayments[pendingPaymentId].processed, "Payment already processed");

        PendingFiatPayment storage payment = pendingPayments[pendingPaymentId];

        // Get the appropriate job ID based on the payment processor
        bytes32 selectedJobId = processorJobIds[payment.processor];

        Chainlink.Request memory request =
            _buildChainlinkRequest(selectedJobId, address(this), this.fulfillPaymentVerification.selector);

        // Build the request with payment data
        request._add("paymentProcessorId", payment.paymentProcessorId);

        // Add the payment processor type (0 for Circle, 1 for Stripe)
        string memory processorType = payment.processor == PaymentProcessor.Circle ? "circle" : "stripe";
        request._add("processor", processorType);

        // Add any processor-specific data if needed
        if (payment.processor == PaymentProcessor.Stripe) {
            // Add Stripe-specific parameters if required
            request._add("currency", payment.currency);
        }

        // Send the request to the Chainlink oracle
        bytes32 requestId = _sendChainlinkRequest(request, fee);

        // Store the association between the Chainlink request and the pending payment
        chainlinkRequests[requestId] = pendingPaymentId;
    }

    /**
     * @dev Legacy function for backward compatibility
     * @param pendingPaymentId The ID of the pending payment to verify
     */
    function verifyCirclePayment(uint256 pendingPaymentId) external onlyOwner {
        verifyPayment(pendingPaymentId);
    }

    /**
     * @dev Specific function for verifying Stripe payments
     * @param pendingPaymentId The ID of the pending payment to verify
     */
    function verifyStripePayment(uint256 pendingPaymentId) external onlyOwner {
        require(pendingPaymentId < nextPendingPaymentId, "Invalid pending payment ID");
        require(!pendingPayments[pendingPaymentId].processed, "Payment already processed");
        PendingFiatPayment storage payment = pendingPayments[pendingPaymentId];
        require(payment.processor == PaymentProcessor.Stripe, "Not a Stripe payment");

        verifyPayment(pendingPaymentId);
    }

    /**
     * @dev Direct callback for Stripe payment verification (not via Chainlink)
     * @param _pendingPaymentId The ID of the pending payment
     * @param _paymentStatus The payment status from Stripe
     * @param _statusReason The reason for the payment status
     */
    function fulfillStripePaymentVerification(
        uint256 _pendingPaymentId,
        uint256 _paymentStatus,
        string calldata _statusReason
    ) external onlyOwner {
        require(_pendingPaymentId > 0 && _pendingPaymentId < nextPendingPaymentId, "Invalid pending payment ID");

        PendingFiatPayment storage payment = pendingPayments[_pendingPaymentId];
        require(!payment.processed, "Payment already processed");
        require(payment.processor == PaymentProcessor.Stripe, "Not a Stripe payment");

        payment.processed = true;

        if (_paymentStatus == 1) {
            // Payment successful, process through the payment gateway
            if (usdcToken.transferFrom(owner(), address(this), payment.amountUSDC)) {
                usdcToken.approve(address(paymentGateway), payment.amountUSDC);

                uint256 paymentGatewayId = paymentGateway.processTokenPayment(
                    address(usdcToken), payment.recipient, payment.amountUSDC, payment.referenceCode
                );

                emit FiatPaymentConfirmed(
                    _pendingPaymentId, paymentGatewayId, payment.paymentProcessorId, payment.processor
                );
            } else {
                emit FiatPaymentFailed(
                    _pendingPaymentId, payment.paymentProcessorId, "USDC transfer failed", payment.processor
                );
            }
        } else {
            // Payment failed
            emit FiatPaymentFailed(_pendingPaymentId, payment.paymentProcessorId, _statusReason, payment.processor);
        }
    }

    /**
     * @dev Callback function for Chainlink oracle response
     * @param _requestId The ID of the Chainlink request
     * @param _paymentStatus The status of the payment (1 = success, 0 = failed)
     * @param _statusReason The reason for the status (only relevant if failed)
     */
    function fulfillPaymentVerification(bytes32 _requestId, uint256 _paymentStatus, string calldata _statusReason)
        external
        recordChainlinkFulfillment(_requestId)
    {
        uint256 pendingPaymentId = chainlinkRequests[_requestId];
        require(pendingPaymentId > 0, "Unknown request ID");

        PendingFiatPayment storage payment = pendingPayments[pendingPaymentId];
        require(!payment.processed, "Payment already processed");

        payment.processed = true;

        if (_paymentStatus == 1) {
            // Payment successful, process through the payment gateway
            if (usdcToken.transferFrom(owner(), address(this), payment.amountUSDC)) {
                usdcToken.approve(address(paymentGateway), payment.amountUSDC);

                uint256 paymentGatewayId = paymentGateway.processTokenPayment(
                    address(usdcToken), payment.recipient, payment.amountUSDC, payment.referenceCode
                );

                emit FiatPaymentConfirmed(
                    pendingPaymentId, paymentGatewayId, payment.paymentProcessorId, payment.processor
                );
            } else {
                emit FiatPaymentFailed(
                    pendingPaymentId, payment.paymentProcessorId, "USDC transfer failed", payment.processor
                );
            }
        } else {
            // Payment failed
            emit FiatPaymentFailed(pendingPaymentId, payment.paymentProcessorId, _statusReason, payment.processor);
        }
    }

    /**
     * @dev Gets the latest exchange rate for a supported currency to USD
     * @param currency The fiat currency code
     * @return The exchange rate with 8 decimals of precision
     */
    function getExchangeRate(string calldata currency) public view returns (int256) {
        AggregatorV3Interface priceFeed = forexPriceFeeds[currency];
        require(address(priceFeed) != address(0), "Unsupported currency");

        (, int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }

    /**
     * @notice Convert fiat currency amount to USDC
     * @param amount Amount in fiat currency (with 6 decimals for simplicity)
     * @param currency Currency code (e.g. "NZD")
     * @return usdcAmount The equivalent amount in USDC tokens (with 6 decimals)
     */
    function convertToUSDC(uint256 amount, string calldata currency) public view returns (uint256 usdcAmount) {
        int256 price = getExchangeRate(currency);
        require(price > 0, "Invalid price feed");

        // Convert amount to USD based on exchange rate
        // Chainlink price feeds return 8 decimals, USDC has 6 decimals
        if (amount > 0) {
            // Convert price to uint256 since it's guaranteed positive
            uint256 priceUint = uint256(price);

            // In the test, we're passing 100 * 10^6 (100 NZD) and the price feed is 61000000 (0.61 USD)
            // The expected result is 61 * 10^6 (61 USDC)
            // Simply multiply amount by price and keep the 6 decimals
            usdcAmount = (amount * priceUint) / 10 ** 8;
        } else {
            usdcAmount = 0;
        }

        return usdcAmount;
    }

    /**
     * @dev Withdraws any LINK tokens to the owner
     */
    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(_chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }

    /**
     * @dev Gets the list of all supported fiat currencies
     * @return Array of supported currency codes
     */
    function getSupportedCurrencies() external view returns (string[] memory) {
        return supportedCurrencies;
    }
}
