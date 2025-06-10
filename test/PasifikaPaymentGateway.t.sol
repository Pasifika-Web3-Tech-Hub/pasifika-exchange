// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import "../src/payment/PasifikaPaymentGateway.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Simple ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract PasifikaPaymentGatewayTest is Test {
    PasifikaPaymentGateway public paymentGateway;
    MockToken public mockToken;

    address public treasury;
    address public user1;
    address public user2;
    address public merchant;

    // Networks supported by Pasifika
    string[] public networks = ["Arbitrum", "RootStock", "Linea"];

    function setUp() public {
        // Setup addresses
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        merchant = makeAddr("merchant");

        // Deploy mock token
        mockToken = new MockToken();

        // Deploy payment gateway for Arbitrum network
        paymentGateway = new PasifikaPaymentGateway(treasury, networks[0]);

        // Setup initial balances
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);

        // Transfer tokens to test users
        mockToken.transfer(user1, 1000 * 10 ** 18);
        mockToken.transfer(user2, 1000 * 10 ** 18);
    }

    function testNativePayment() public {
        // Configure user as member (tier 1) - 0.50% fee
        vm.prank(address(paymentGateway.owner()));
        paymentGateway.updateUserTier(user1, 1);

        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 merchantBalanceBefore = merchant.balance;

        // Process payment
        vm.prank(user1);
        uint256 paymentAmount = 1 ether;
        uint256 paymentId = paymentGateway.processNativePayment{value: paymentAmount}(merchant, "Order-123");

        // Verify receipt
        PasifikaPaymentGateway.Receipt memory receipt = paymentGateway.getReceipt(paymentId);

        // Calculate expected fee (0.5%)
        uint256 expectedFee = (paymentAmount * 50) / 10000; // 0.50% fee for member
        uint256 expectedMerchantAmount = paymentAmount - expectedFee;

        // Verify balances
        assertEq(treasury.balance, treasuryBalanceBefore + expectedFee);
        assertEq(merchant.balance, merchantBalanceBefore + expectedMerchantAmount);

        // Verify receipt details
        assertEq(receipt.payer, user1);
        assertEq(receipt.paymentToken, address(0)); // native token
        assertEq(receipt.amount, paymentAmount);
        assertEq(receipt.feeAmount, expectedFee);
        assertEq(receipt.completed, true);
        assertEq(keccak256(abi.encodePacked(receipt.referenceCode)), keccak256(abi.encodePacked("Order-123")));
        assertEq(keccak256(abi.encodePacked(receipt.networkName)), keccak256(abi.encodePacked(networks[0])));
    }

    function testTokenPayment() public {
        // Configure user as node operator (tier 2) - 0.25% fee
        vm.prank(address(paymentGateway.owner()));
        paymentGateway.updateUserTier(user2, 2);

        uint256 treasuryTokenBalanceBefore = mockToken.balanceOf(treasury);
        uint256 merchantTokenBalanceBefore = mockToken.balanceOf(merchant);

        // Approve tokens
        vm.startPrank(user2);
        uint256 paymentAmount = 100 * 10 ** 18; // 100 tokens
        mockToken.approve(address(paymentGateway), paymentAmount);

        // Process payment
        uint256 paymentId =
            paymentGateway.processTokenPayment(address(mockToken), merchant, paymentAmount, "Token-Order-456");
        vm.stopPrank();

        // Verify receipt
        PasifikaPaymentGateway.Receipt memory receipt = paymentGateway.getReceipt(paymentId);

        // Calculate expected fee (0.25%)
        uint256 expectedFee = (paymentAmount * 25) / 10000; // 0.25% fee for node operator
        uint256 expectedMerchantAmount = paymentAmount - expectedFee;

        // Verify token balances
        assertEq(mockToken.balanceOf(treasury), treasuryTokenBalanceBefore + expectedFee);
        assertEq(mockToken.balanceOf(merchant), merchantTokenBalanceBefore + expectedMerchantAmount);

        // Verify receipt details
        assertEq(receipt.payer, user2);
        assertEq(receipt.paymentToken, address(mockToken));
        assertEq(receipt.amount, paymentAmount);
        assertEq(receipt.feeAmount, expectedFee);
        assertEq(receipt.completed, true);
        assertEq(keccak256(abi.encodePacked(receipt.referenceCode)), keccak256(abi.encodePacked("Token-Order-456")));
        assertEq(keccak256(abi.encodePacked(receipt.networkName)), keccak256(abi.encodePacked(networks[0])));
    }

    function testFeeRates() public {
        // Default rates should be:
        // Guest (tier 0): 1.00% = 100 basis points
        // Member (tier 1): 0.50% = 50 basis points
        // Node operator (tier 2): 0.25% = 25 basis points

        assertEq(paymentGateway.guestFee(), 100);
        assertEq(paymentGateway.memberFee(), 50);
        assertEq(paymentGateway.nodeOperatorFee(), 25);

        // Update rates
        vm.prank(address(paymentGateway.owner()));
        paymentGateway.updateFeeRates(150, 75, 30);

        // Verify updated rates
        assertEq(paymentGateway.guestFee(), 150);
        assertEq(paymentGateway.memberFee(), 75);
        assertEq(paymentGateway.nodeOperatorFee(), 30);
    }

    function testNetworkNameUpdate() public {
        // Initial network should be Arbitrum
        PasifikaPaymentGateway.Receipt memory receipt;

        // Process a payment
        vm.prank(user1);
        uint256 paymentId = paymentGateway.processNativePayment{value: 0.1 ether}(merchant, "Network-Test-1");

        // Verify network name
        receipt = paymentGateway.getReceipt(paymentId);
        assertEq(keccak256(abi.encodePacked(receipt.networkName)), keccak256(abi.encodePacked(networks[0])));

        // Update network name to RootStock
        vm.prank(address(paymentGateway.owner()));
        paymentGateway.updateNetworkName(networks[1]);

        // Process another payment
        vm.prank(user1);
        paymentId = paymentGateway.processNativePayment{value: 0.1 ether}(merchant, "Network-Test-2");

        // Verify updated network name
        receipt = paymentGateway.getReceipt(paymentId);
        assertEq(keccak256(abi.encodePacked(receipt.networkName)), keccak256(abi.encodePacked(networks[1])));

        // Update network name to Linea
        vm.prank(address(paymentGateway.owner()));
        paymentGateway.updateNetworkName(networks[2]);

        // Process another payment
        vm.prank(user1);
        paymentId = paymentGateway.processNativePayment{value: 0.1 ether}(merchant, "Network-Test-3");

        // Verify updated network name
        receipt = paymentGateway.getReceipt(paymentId);
        assertEq(keccak256(abi.encodePacked(receipt.networkName)), keccak256(abi.encodePacked(networks[2])));
    }
}
