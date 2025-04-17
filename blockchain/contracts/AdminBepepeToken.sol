/**
 * @file contracts/AdminBepepeToken.sol
 * Submitted for verification at BscScan.com on 2025-04-16
 * Compiler: Solidity ^0.8.28
 * License: MIT
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBepepeAdmin.sol";

/**
 * @dev Admin contract storing payment token prices, etc.
 *      Only the owner here can do updates. Not verified publicly if you prefer,
 *      but it remains visible on-chain.
 */
contract AdminBepepeToken is Ownable, IBepepeAdmin {
    using SafeERC20 for IERC20;

    mapping(address => uint256) private _paymentTokenPrices;

    // Example of an admin mint function: you could store a reference to UserBepepeToken or do a direct call.
    // Or rely on your own bridging approach. Omitted for brevity.

    function getPaymentTokenPrice(address token) external view override returns (uint256) {
        return _paymentTokenPrices[token];
    }

    function setPaymentTokenPrice(address token, uint256 price) external onlyOwner {
        _paymentTokenPrices[token] = price;
    }

    function withdrawPaymentToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function withdrawBNB() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {}
}
