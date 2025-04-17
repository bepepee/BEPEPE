/**
 * @file contracts/MockERC20.sol
 * Submitted for verification at BscScan.com on 2025-04-16
 * Compiler: Solidity ^0.8.28
 * License: MIT
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Simple mock ERC20 for testing.
 */
contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}
