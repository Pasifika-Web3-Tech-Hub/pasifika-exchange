// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/oracles/PasifikaPriceFeed.sol";

contract DeployPasifikaPriceFeed is Script {
    function run() public returns (PasifikaPriceFeed) {
        // Get ETH/USD price feed from environment or use default
        address ethUsdPriceFeed;

        try vm.envAddress("ETH_USD_FEED") returns (address feed) {
            ethUsdPriceFeed = feed;
        } catch {
            // Default to Arbitrum Sepolia ETH/USD feed
            ethUsdPriceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        }

        console.log("Using ETH/USD feed at:", ethUsdPriceFeed);

        vm.startBroadcast();

        PasifikaPriceFeed priceFeed = new PasifikaPriceFeed(ethUsdPriceFeed);

        vm.stopBroadcast();

        console.log("PasifikaPriceFeed deployed at: %s", address(priceFeed));

        return priceFeed;
    }
}
