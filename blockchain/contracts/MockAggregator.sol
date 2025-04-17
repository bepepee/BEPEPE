/**
 * @file contracts/MockAggregator.sol
 * Submitted for verification at BscScan.com on 2025-04-16
 * Compiler: Solidity ^0.8.28
 * License: MIT
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/AggregatorV3Interface.sol";

contract MockAggregator is AggregatorV3Interface {
    uint8 public override decimals = 8;
    string public override description = "Mock Price Feed";
    uint256 public override version = 1;
    int256 private _price;

    constructor(int256 initialPrice) {
        _price = initialPrice;
    }

    function getRoundData(
        uint80
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, _price, 0, 0, 0);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, _price, 0, 0, 0);
    }
}
