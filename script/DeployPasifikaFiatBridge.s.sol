// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import "../src/payment/PasifikaFiatBridge.sol";
import "../src/payment/PasifikaPaymentGateway.sol";
import "./DeployPasifikaPaymentGateway.s.sol";

/**
 * @title DeployPasifikaFiatBridge
 * @dev Deployment script for the PasifikaFiatBridge contract
 * @notice Supports deployment across Arbitrum, RootStock, and Linea networks
 */
contract DeployPasifikaFiatBridge is Script {
    function run() public returns (PasifikaFiatBridge) {
        // Deploy payment gateway or use existing one
        PasifikaPaymentGateway paymentGateway;

        // Check if we should deploy a new payment gateway or use an existing one
        if (vm.envOr("DEPLOY_PAYMENT_GATEWAY", true)) {
            // Deploy a new payment gateway
            DeployPasifikaPaymentGateway deployPaymentGateway = new DeployPasifikaPaymentGateway();
            paymentGateway = deployPaymentGateway.run();
        } else {
            try vm.envAddress("PAYMENT_GATEWAY_ADDRESS") returns (address paymentGatewayAddress) {
                // Use an existing payment gateway from environment variable
                console.log("Using existing payment gateway at:", paymentGatewayAddress);
                paymentGateway = PasifikaPaymentGateway(paymentGatewayAddress);
            } catch {
                // Deploy a new payment gateway as fallback
                console.log("No PAYMENT_GATEWAY_ADDRESS environment variable found, deploying new payment gateway");
                DeployPasifikaPaymentGateway deployPaymentGateway = new DeployPasifikaPaymentGateway();
                paymentGateway = deployPaymentGateway.run();
            }
        }

        // Get deployment parameters from environment variables or use defaults
        address usdcToken = vm.envOr("USDC_ADDRESS", address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)); // Default to Mainnet USDC
        address chainlinkToken = vm.envOr("LINK_TOKEN_ADDRESS", address(0x514910771AF9Ca656af840dff83E8264EcF986CA)); // Default to Mainnet LINK
        address oracle = vm.envOr("CHAINLINK_ORACLE_ADDRESS", address(0x00000000000000000000000000000000000000A1)); // Placeholder
        bytes32 circleJobId = vm.envOr(
            "CHAINLINK_CIRCLE_JOB_ID", bytes32(0x3862306630303966616335343461653938626633386166363935383735316664)
        ); // Circle JobId
        bytes32 stripeJobId = vm.envOr(
            "CHAINLINK_STRIPE_JOB_ID", bytes32(0x1234567890123456789012345678901234567890123456789012345678901234)
        ); // Stripe JobId
        uint256 fee = vm.envOr("CHAINLINK_FEE", uint256(10 * 10 ** 17)); // Default 1.0 LINK
        address treasury = vm.envOr("TREASURY_ADDRESS", paymentGateway.treasuryAddress()); // Use payment gateway treasury as default

        // Print deployment information
        string memory networkName = paymentGateway.currentNetwork();
        console.log("Deploying PasifikaFiatBridge to %s network", networkName);
        console.log("Using PasifikaPaymentGateway at: %s", address(paymentGateway));
        console.log("USDC Token address: %s", usdcToken);
        console.log("LINK Token address: %s", chainlinkToken);
        console.log("Chainlink Oracle address: %s", oracle);
        console.log("Treasury address: %s", treasury);
        console.log("Circle JobId: %s", uint256(circleJobId));
        console.log("Stripe JobId: %s", uint256(stripeJobId));

        vm.startBroadcast();

        // Deploy the fiat bridge contract with multi-processor support
        PasifikaFiatBridge fiatBridge = new PasifikaFiatBridge(
            usdcToken, address(paymentGateway), chainlinkToken, oracle, circleJobId, stripeJobId, fee, treasury
        );

        vm.stopBroadcast();

        console.log("PasifikaFiatBridge deployed at: %s", address(fiatBridge));

        return fiatBridge;
    }
}
