/**
 * @file contracts/IBepepeAdmin.sol
 * Submitted for verification at BscScan.com on 2025-04-16
 * Compiler: Solidity ^0.8.28
 * License: MIT
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBepepeAdmin {
    function getPaymentTokenPrice(address token) external view returns (uint256);
}
