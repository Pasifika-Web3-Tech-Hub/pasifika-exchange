// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PasifikaPriceFeed} from "../src/oracles/PasifikaPriceFeed.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Mock aggregator for testing
contract MockAggregatorV3 is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;

    constructor(int256 initialPrice, uint8 decimals) {
        _price = initialPrice;
        _decimals = decimals;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, block.timestamp, block.timestamp, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }

    // Helper function to update the price
    function updatePrice(int256 newPrice) external {
        _price = newPrice;
    }
}

contract PasifikaPriceFeedTest is Test {
    PasifikaPriceFeed public priceFeed;
    MockAggregatorV3 public ethUsdFeed;
    MockAggregatorV3 public topUsdFeed;
    MockAggregatorV3 public usdcUsdFeed;

    address public owner;
    address public user1;
    address public ethToken;
    address public topToken;
    address public usdcToken;

    // Using smaller test values to avoid overflow
    int256 constant ETH_USD_PRICE = 250 * 10 ** 6; // $2.50 with 8 decimals
    int256 constant USDC_USD_PRICE = 100 * 10 ** 6; // $1.00 with 8 decimals
    int256 constant TOP_USD_PRICE = 41 * 10 ** 6; // $0.41 with 8 decimals

    function setUp() public {
        // Set up accounts
        owner = makeAddr("owner");
        user1 = makeAddr("user1");

        // Set up token addresses
        ethToken = makeAddr("ethToken");
        topToken = makeAddr("topToken");
        usdcToken = makeAddr("usdcToken");

        // Create mock price feeds with 8 decimals (Chainlink standard)
        ethUsdFeed = new MockAggregatorV3(ETH_USD_PRICE, 8);
        topUsdFeed = new MockAggregatorV3(TOP_USD_PRICE, 8);
        usdcUsdFeed = new MockAggregatorV3(USDC_USD_PRICE, 8);

        vm.startPrank(owner);

        // Deploy price feed contract
        priceFeed = new PasifikaPriceFeed(address(ethUsdFeed));

        // Set up price feeds
        priceFeed.setPriceFeed(topToken, address(topUsdFeed));
        priceFeed.setPriceFeed(usdcToken, address(usdcUsdFeed));

        vm.stopPrank();
    }

    function testGetEthUsdPrice() public view {
        int256 ethPrice = priceFeed.getLatestETHPrice();
        assertEq(ethPrice, ETH_USD_PRICE);
    }

    function testGetTokenPrices() public view {
        int256 topPrice = priceFeed.getLatestPrice(topToken);
        int256 usdcPrice = priceFeed.getLatestPrice(usdcToken);

        assertEq(topPrice, TOP_USD_PRICE);
        assertEq(usdcPrice, USDC_USD_PRICE);
    }

    function testTokenToUSDConversion() public view {
        // Use a smaller amount to avoid overflow
        uint256 topAmount = 1 * 10 ** 18; // 1 TOP with 18 decimals

        uint256 usdAmount = priceFeed.convertTokenToUSD(topToken, topAmount);

        // Expected USD value: 1 * $0.41 = $0.41 with 8 decimals
        // The formula in the contract now uses: (amount / 10^10) * price / 10^decimals
        uint256 expectedUsdAmount = (topAmount / 10 ** 10) * uint256(TOP_USD_PRICE) / 10 ** 8;

        assertEq(usdAmount, expectedUsdAmount);
    }

    function testUSDToTokenConversion() public view {
        // Use a smaller amount to avoid overflow
        uint256 usdAmount = 1 * 10 ** 8; // $1 with 8 decimals

        uint256 topAmount = priceFeed.convertUSDToToken(topToken, usdAmount);

        // Expected TOP amount: $1 / $0.41
        // The formula in the contract is now: (usdAmount * 10^10) / price
        uint256 expectedTopAmount = (usdAmount * 10 ** 10) / uint256(TOP_USD_PRICE);

        assertEq(topAmount, expectedTopAmount);
    }

    function testOnlyOwnerCanSetPriceFeeds() public {
        // Non-owner should not be able to set price feeds
        vm.startPrank(user1);
        vm.expectRevert();
        priceFeed.setPriceFeed(topToken, address(1));

        vm.expectRevert();
        priceFeed.updateEthUsdPriceFeed(address(1));
        vm.stopPrank();

        // Owner should be able to set price feeds
        vm.startPrank(owner);
        priceFeed.setPriceFeed(topToken, address(topUsdFeed)); // This should succeed
        priceFeed.updateEthUsdPriceFeed(address(ethUsdFeed)); // This should succeed
        vm.stopPrank();
    }

    function testUpdatePriceFeed() public {
        // First check the current price
        int256 currentPrice = priceFeed.getLatestPrice(topToken);
        assertEq(currentPrice, TOP_USD_PRICE);

        vm.startPrank(owner);

        // Create a new price feed with updated price (0.45 USD)
        int256 newPrice = 45 * 10 ** 6; // $0.45 with 8 decimals
        MockAggregatorV3 newTopUsdFeed = new MockAggregatorV3(newPrice, 8);

        // Update the price feed
        priceFeed.setPriceFeed(topToken, address(newTopUsdFeed));

        vm.stopPrank();

        // Check the updated price
        int256 newTopPrice = priceFeed.getLatestPrice(topToken);
        assertEq(newTopPrice, newPrice);
    }

    function testUpdateEthUsdPriceFeed() public {
        // First check the current price
        int256 currentPrice = priceFeed.getLatestETHPrice();
        assertEq(currentPrice, ETH_USD_PRICE);

        vm.startPrank(owner);

        // Create a new ETH/USD price feed (3.00 USD)
        int256 newPrice = 300 * 10 ** 6; // $3.00 with 8 decimals
        MockAggregatorV3 newEthUsdFeed = new MockAggregatorV3(newPrice, 8);

        // Update the ETH/USD price feed
        priceFeed.updateEthUsdPriceFeed(address(newEthUsdFeed));

        vm.stopPrank();

        // Check the updated price
        int256 newEthPrice = priceFeed.getLatestETHPrice();
        assertEq(newEthPrice, newPrice);
    }

    function testGetDecimals() public view {
        uint8 decimals = priceFeed.getPriceFeedDecimals(topToken);
        assertEq(decimals, 8); // Our mock price feeds have 8 decimals
    }

    function testRevertOnInvalidPriceFeed() public {
        address invalidToken = makeAddr("invalidToken");

        // Should revert when trying to get price for token without price feed
        vm.expectRevert("Price feed not found");
        priceFeed.getLatestPrice(invalidToken);

        // Should revert when trying to convert token to USD
        vm.expectRevert("Price feed not found");
        priceFeed.convertTokenToUSD(invalidToken, 100 * 10 ** 18);

        // Should revert when trying to convert USD to token
        vm.expectRevert("Price feed not found");
        priceFeed.convertUSDToToken(invalidToken, 50 * 10 ** 8);
    }
}
