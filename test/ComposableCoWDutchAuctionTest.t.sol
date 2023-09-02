// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import "composable-test/ComposableCoW.base.t.sol";
import "composable/interfaces/IAggregatorV3Interface.sol";
import "../src/DutchAuction.sol";

contract ComposableCoWDutchAuctionTest is BaseComposableCoWTest {
    IERC20 constant SELL_TOKEN = IERC20(address(0x1));
    IERC20 constant BUY_TOKEN = IERC20(address(0x2));
    address constant SELL_ORACLE = address(0x3);
    address constant BUY_ORACLE = address(0x4);
    bytes32 constant APP_DATA = bytes32(0x0);

    DutchAuction dutchAuction;
    address safe;

    function setUp() public virtual override(BaseComposableCoWTest) {
        super.setUp();

        dutchAuction = new DutchAuction();
    }

    function mockOracle(address mock, int256 price) internal returns (IAggregatorV3Interface iface) {
        iface = IAggregatorV3Interface(mock);
        vm.mockCall(mock, abi.encodeWithSelector(iface.latestRoundData.selector), abi.encode(0, price, 0, 0, 0));
        vm.mockCall(mock, abi.encodeWithSelector(iface.decimals.selector), abi.encode(18));
    }

    function mockOracle(address mock, int256 price, uint256 decimals) internal returns (IAggregatorV3Interface iface) {
        iface = IAggregatorV3Interface(mock);
        vm.mockCall(mock, abi.encodeWithSelector(iface.latestRoundData.selector), abi.encode(0, price, 0, 0, 0));
        vm.mockCall(mock, abi.encodeWithSelector(iface.decimals.selector), abi.encode(decimals));
    }

    function test_limitPriceAtStart_concrete() public {
        DutchAuction.Data memory data = DutchAuction.Data({
            sellToken: SELL_TOKEN,
            buyToken: BUY_TOKEN,
            sellAmount: 1 ether,
            appData: APP_DATA,
            receiver: address(0x0),
            isPartiallyFillable: false,
            sellTokenPriceOracle: mockOracle(SELL_ORACLE, 2 ether),
            buyTokenPriceOracle: mockOracle(BUY_ORACLE, 1 ether),
            startTs: 1_000_000,
            duration: 600,
            timeStep: 60,
            startPrice: 2 ether,
            endPrice: 1 ether
        });
        vm.warp(1_000_000);

        GPv2Order.Data memory res =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));

        assertEq(res.buyAmount, 2 ether);
    }

    function test_limitPriceAtEnd_concrete() public {
        DutchAuction.Data memory data = DutchAuction.Data({
            sellToken: SELL_TOKEN,
            buyToken: BUY_TOKEN,
            sellAmount: 1 ether,
            appData: APP_DATA,
            receiver: address(0x0),
            isPartiallyFillable: false,
            sellTokenPriceOracle: mockOracle(SELL_ORACLE, 2 ether),
            buyTokenPriceOracle: mockOracle(BUY_ORACLE, 1 ether),
            startTs: 1_000_000,
            // multiples of 10 avoids rounding issues
            duration: 100,
            timeStep: 10,
            startPrice: 2 ether,
            endPrice: 1 ether
        });
        vm.warp(1_000_100);

        GPv2Order.Data memory res =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));

        assertEq(res.buyAmount, 1 ether);
    }

    function test_limitPriceAtMiddle_concrete() public {
        DutchAuction.Data memory data = DutchAuction.Data({
            sellToken: SELL_TOKEN,
            buyToken: BUY_TOKEN,
            sellAmount: 1 ether,
            appData: APP_DATA,
            receiver: address(0x0),
            isPartiallyFillable: false,
            sellTokenPriceOracle: mockOracle(SELL_ORACLE, 2 ether),
            buyTokenPriceOracle: mockOracle(BUY_ORACLE, 1 ether),
            startTs: 1_000_000,
            // multiples of 10 avoids rounding issues
            duration: 100,
            timeStep: 10,
            startPrice: 2 ether,
            endPrice: 1 ether
        });
        vm.warp(1_000_050);

        GPv2Order.Data memory res =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));

        assertEq(res.buyAmount, 15 * 10 ** 17);
    }

    function test_limitPriceWithinBounds_fuzz(uint256 timePassed, uint32 duration) public {
        vm.assume(timePassed <= 100);
        vm.assume(timePassed > 0);
        vm.assume(timePassed <= duration);
        vm.assume(duration <= 3600);
        vm.assume(duration > 0);

        DutchAuction.Data memory data = DutchAuction.Data({
            sellToken: SELL_TOKEN,
            buyToken: BUY_TOKEN,
            sellAmount: 1 ether,
            appData: APP_DATA,
            receiver: address(0x0),
            isPartiallyFillable: false,
            sellTokenPriceOracle: mockOracle(SELL_ORACLE, 2 ether),
            buyTokenPriceOracle: mockOracle(BUY_ORACLE, 1 ether),
            startTs: 1_000_000,
            duration: duration,
            timeStep: 10,
            startPrice: 2 ether,
            endPrice: 1 ether
        });
        vm.warp(1_000_000 + timePassed);

        GPv2Order.Data memory res =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));

        assertGe(res.buyAmount, 1 ether);
        assertLe(res.buyAmount, 2 ether);
    }

    bytes32 domainSeparator = 0x8f05589c4b810bc2f706854508d66d447cd971f8354a4bb0b3471ceb0a466bc7;

    function test_verifyOrder() public {
        DutchAuction.Data memory data = DutchAuction.Data({
            sellToken: SELL_TOKEN,
            buyToken: BUY_TOKEN,
            sellAmount: 5 * 10 ** 16,
            appData: APP_DATA,
            receiver: address(0x0),
            isPartiallyFillable: false,
            sellTokenPriceOracle: mockOracle(SELL_ORACLE, 188620000000, 8),
            buyTokenPriceOracle: mockOracle(BUY_ORACLE, 11786941523, 8),
            startTs: 1_000_000,
            duration: 600,
            timeStep: 120,
            startPrice: uint256(188620000000),
            endPrice: uint256(188620000000) * 90 / 100
        });
        vm.warp(1_000_000);
        GPv2Order.Data memory empty;
        GPv2Order.Data memory order =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));
        bytes32 hash_ = GPv2Order.hash(order, domainSeparator);
        vm.warp(1_000_000 + 79);

        dutchAuction.verify(safe, address(0), hash_, domainSeparator, bytes32(0), abi.encode(data), bytes(""), empty);
    }

    function test_limitPriceIntegration() public {
        DutchAuction.Data memory data = DutchAuction.Data({
            sellToken: SELL_TOKEN,
            buyToken: BUY_TOKEN,
            sellAmount: 5 * 10 ** 16,
            appData: APP_DATA,
            receiver: address(0x0),
            isPartiallyFillable: false,
            sellTokenPriceOracle: mockOracle(SELL_ORACLE, 188620000000, 8),
            buyTokenPriceOracle: mockOracle(BUY_ORACLE, 11786941523, 8),
            startTs: 1_000_000,
            duration: 100,
            timeStep: 10,
            startPrice: uint256(188620000000),
            endPrice: uint256(188620000000) * 90 / 100
        });
        vm.warp(1_000_000 + 50);

        GPv2Order.Data memory res =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));

        assertLe(res.buyAmount, 8 * 10 ** 17);
        assertGe(res.buyAmount, 6 * 10 ** 17);
    }

    // TODO: fix different token decimal buy amounts
}
