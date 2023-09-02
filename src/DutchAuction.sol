// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import "composable/BaseConditionalOrder.sol";
import "composable/interfaces/IAggregatorV3Interface.sol";

contract DutchAuction is BaseConditionalOrder {
    struct Data {
        IERC20 sellToken;
        IERC20 buyToken;
        uint256 sellAmount;
        bytes32 appData;
        address receiver;
        bool isPartiallyFillable;
        // the time the auction starts
        uint32 startTs;
        // how long the auction will run for
        uint32 duration;
        // time step, after each step a new order with adjusted limit price is emitted
        uint32 timeStep;
        // == Curve parameters ==
        // both oracles need to use the same numeraire
        IAggregatorV3Interface sellTokenPriceOracle;
        IAggregatorV3Interface buyTokenPriceOracle;
        // start and end price need to be in the oracle numeraire
        // expected as sell token / buy token price
        uint256 startPrice;
        uint256 endPrice;
    }

    function getTradeableOrder(address, address, bytes32, bytes calldata staticInput, bytes calldata)
        public
        view
        override
        returns (GPv2Order.Data memory order)
    {
        Data memory data = abi.decode(staticInput, (Data));
        uint32 currentTs = (uint32(block.timestamp) / data.timeStep) * data.timeStep;
        uint256 x;
        // due to rounding/binning current ts might be in the past
        if (currentTs < data.startTs) {
            x = 0;
        } else {
            // calculate x in terms of dx steps
            x = ((currentTs - data.startTs) / data.timeStep) * data.timeStep;
        }

        if (x > data.duration) {
            // the order is too old
            revert IConditionalOrder.OrderNotValid("TOO_OLD");
        }

        (, int256 latestSellPrice,,,) = data.sellTokenPriceOracle.latestRoundData();
        (, int256 latestBuyPrice,,,) = data.buyTokenPriceOracle.latestRoundData();
        uint256 decimals = data.sellTokenPriceOracle.decimals();
        // calculate new limit price by using a slope between start and end price,
        // use the current oracle prices as intercept
        uint256 currentPrice = (uint256(latestSellPrice) * 10 ** decimals) / uint256(latestBuyPrice);
        uint256 normalisedStartPrice = data.startPrice * 10 ** decimals / uint256(latestBuyPrice);
        uint256 normalisedEndPrice = data.endPrice * 10 ** decimals / uint256(latestBuyPrice);
        // subtract price decrease per passed time
        // Note: due to rounding issues the limit price might sometimes be slightly higher than expected
        uint256 limitPrice = currentPrice - (((normalisedStartPrice - normalisedEndPrice) / data.duration) * x);
        // order is valid until the next timestep
        uint32 validTo = currentTs + data.timeStep;

        order = GPv2Order.Data(
            data.sellToken,
            data.buyToken,
            data.receiver,
            data.sellAmount,
            (data.sellAmount * limitPrice) / 10 ** decimals,
            validTo,
            data.appData,
            0, // use zero fee for limit orders
            GPv2Order.KIND_SELL, // only sell order support for now
            data.isPartiallyFillable,
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );
    }
}