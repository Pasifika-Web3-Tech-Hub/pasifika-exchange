// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import "../src/payment/PasifikaPaymentGateway.sol";

/**
 * @title DeployPasifikaPaymentGateway
 * @dev Deployment script for the PasifikaPaymentGateway contract
 * @notice Supports deployment across Arbitrum, RootStock, and Linea networks
 */
contract DeployPasifikaPaymentGateway is Script {
    function run() public returns (PasifikaPaymentGateway) {
        // Get deployment parameters from environment variables or use defaults
        address treasuryAddress = vm.envOr("TREASURY_ADDRESS", address(0x1234567890123456789012345678901234567890));
        string memory networkName = vm.envOr("NETWORK_NAME", string("Arbitrum"));

        // Print deployment information
        console.log("Deploying PasifikaPaymentGateway to %s network", networkName);
        console.log("Treasury address: %s", treasuryAddress);

        vm.startBroadcast();

        // Deploy the payment gateway contract
        PasifikaPaymentGateway paymentGateway = new PasifikaPaymentGateway(
            treasuryAddress,
            networkName
        );

        vm.stopBroadcast();

        console.log("PasifikaPaymentGateway deployed at: %s", address(paymentGateway));

        return paymentGateway;
    }
}
