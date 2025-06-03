// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/oracles/PasifikaPriceFeed.sol";
import "../src/exchange/PasifikaExchange.sol";
import "./DeployPasifikaPriceFeed.s.sol";

contract DeployPasifikaExchange is Script {
    function run() public returns (PasifikaExchange) {
        // Deploy price feed or use existing one
        PasifikaPriceFeed priceFeed;

        // Check if we should deploy a new price feed or use an existing one
        if (vm.envOr("DEPLOY_PRICE_FEED", true)) {
            // Deploy a new price feed
            DeployPasifikaPriceFeed deployPriceFeed = new DeployPasifikaPriceFeed();
            priceFeed = deployPriceFeed.run();
        } else {
            try vm.envAddress("PRICE_FEED_ADDRESS") returns (address priceFeedAddress) {
                // Use an existing price feed from environment variable
                console.log("Using existing price feed at:", priceFeedAddress);
                priceFeed = PasifikaPriceFeed(priceFeedAddress);
            } catch {
                // Deploy a new price feed as fallback
                console.log("No PRICE_FEED_ADDRESS environment variable found, deploying new price feed");
                DeployPasifikaPriceFeed deployPriceFeed = new DeployPasifikaPriceFeed();
                priceFeed = deployPriceFeed.run();
            }
        }

        vm.startBroadcast();

        // Deploy the exchange contract
        PasifikaExchange exchange = new PasifikaExchange(address(priceFeed));

        vm.stopBroadcast();

        console.log("PasifikaExchange deployed at: %s", address(exchange));

        return exchange;
    }
}
