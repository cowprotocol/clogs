// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import "composable-test/ComposableCoW.base.t.sol";
import "../src/DutchAuction.sol";

contract DutchAuctionTest is BaseComposableCoWTest {
    IERC20 constant SELL_TOKEN = IERC20(address(0x1));
    IERC20 constant BUY_TOKEN = IERC20(address(0x2));
    address constant SELL_ORACLE = address(0x3);
    address constant BUY_ORACLE = address(0x4);
    address constant COMPOSABLE_COW = address(0x5);
    bytes32 constant APP_DATA = bytes32(0x0);

    DutchAuction dutchAuction;
    address safe;

    function setUp() public virtual override(BaseComposableCoWTest) {
        super.setUp();

        dutchAuction = new DutchAuction(ComposableCoW(COMPOSABLE_COW));
    }

    function test_limitPriceAtStart_concrete() public {
        DutchAuction.Data memory data = helper_testData();
        vm.warp(data.startTime);

        GPv2Order.Data memory res =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));

        assertEq(res.buyAmount, 10 ether);
    }

    function test_limitPriceAtEnd_concrete() public {
        DutchAuction.Data memory data = helper_testData();
        vm.warp(data.startTime - 1 + data.stepDuration * data.numSteps);

        GPv2Order.Data memory res =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));

        assertEq(res.buyAmount, 9 ether);
    }

    function test_limitPriceAtMiddle_concrete() public {
        DutchAuction.Data memory data = helper_testData();
        vm.warp(data.startTime - 1 + data.stepDuration * (data.numSteps / 2));

        GPv2Order.Data memory res =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));

        assertEq(res.buyAmount, 9.6 ether);
    }

    function test_verifyOrder() public {
        bytes32 domainSeparator = 0x8f05589c4b810bc2f706854508d66d447cd971f8354a4bb0b3471ceb0a466bc7;

        DutchAuction.Data memory data = helper_testData();
        vm.warp(1_000_000);
        GPv2Order.Data memory empty;
        GPv2Order.Data memory order =
            dutchAuction.getTradeableOrder(safe, address(0), bytes32(0), abi.encode(data), bytes(""));
        bytes32 hash_ = GPv2Order.hash(order, domainSeparator);
        vm.warp(1_000_000 + 79);

        dutchAuction.verify(safe, address(0), hash_, domainSeparator, bytes32(0), abi.encode(data), bytes(""), empty);
    }

    function helper_testData() internal view returns (DutchAuction.Data memory data) {
        return DutchAuction.Data({
            sellToken: token0,
            buyToken: token1,
            receiver: address(0x0),
            sellAmount: 1 ether,
            appData: APP_DATA,
            startTime: 1_000_000,
            startBuyAmount: 10 ether,
            stepDuration: 5 minutes,
            stepDiscount: 200, // 2%
            numSteps: 6, // total 10% discount
            buyTokenBalance: 0
        });
    }
}
