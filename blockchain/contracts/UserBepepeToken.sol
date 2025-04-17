/**
 * @file contracts/UserBepepeToken.sol
 * Submitted for verification at BscScan.com on 2025-04-16
 * Compiler: Solidity ^0.8.28
 * License: MIT
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol"; // Import Ownable;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/AggregatorV3Interface.sol";
import "./interfaces/IBepepeAdmin.sol";

/**
 * @title UserBepepeToken
 * @dev BEPEPE token (user-facing). Users can buy and sell tokens at a fixed $7 price
 *      using Chainlink for BNB/USD and an external admin contract for ERC20 payment token pricing.
 *      This contract also allows the owner to mint additional tokens in the future if needed.
 */
contract UserBepepeToken is ERC20, Ownable {
    using SafeERC20 for IERC20;

    AggregatorV3Interface public bnbUsdPriceFeed;
    IBepepeAdmin public adminContract;

    // Fixed price for BEPEPE tokens: $7 per token (scaled to 18 decimals)
    uint256 public constant TOKEN_PRICE_USD = 7 * 1e18;
    string public logoURI;

    event TokensPurchased(
        address indexed buyer,
        uint256 bepepeAmount,
        uint256 cost
    );
    event TokensSwapped(
        address indexed user,
        uint256 bepepeAmount,
        address paymentToken,
        uint256 paymentAmount
    );

    /**
     * @param initialSupply The total initial tokens to mint.
     * @param priceFeedAddr Address of the BNB/USD Chainlink aggregator.
     * @param initialLogoURI The metadata logo URI.
     * @param adminAddr Address of the external admin contract.
     *
     * @dev The entire initial supply is minted to msg.sender (the deployer/owner).
     */
    constructor(
        uint256 initialSupply,
        address priceFeedAddr,
        string memory initialLogoURI,
        address adminAddr
    ) ERC20("BEPEPE", "PEPE") {
        // Mint the entire initial supply to the deployer/owner.
        _mint(msg.sender, initialSupply);
        bnbUsdPriceFeed = AggregatorV3Interface(priceFeedAddr);
        logoURI = initialLogoURI;
        adminContract = IBepepeAdmin(adminAddr);
    }

    /**
     * @notice Allows users to buy tokens with BNB, pegged at $7 each.
     */
    function buyTokens() external payable {
        require(msg.value > 0, "No BNB sent");
        (, int256 bnbUsdPrice, , , ) = bnbUsdPriceFeed.latestRoundData();
        require(bnbUsdPrice > 0, "Invalid price feed");
        uint256 bnbPrice = uint256(bnbUsdPrice);

        // Convert incoming BNB to USD (scaled to 18 decimals) then determine token amount.
        uint256 bnbValueInUsd18 = (msg.value * bnbPrice) / 1e8;
        uint256 tokensToBuy = bnbValueInUsd18 / TOKEN_PRICE_USD;
        require(tokensToBuy > 0, "Not enough BNB for 1 token");
        require(
            balanceOf(address(this)) >= tokensToBuy,
            "Not enough tokens in contract"
        );

        _transfer(address(this), msg.sender, tokensToBuy);
        emit TokensPurchased(msg.sender, tokensToBuy, msg.value);
    }

    /**
     * @notice Allows users to buy tokens with an ERC20 token using a price from the external admin contract.
     * @param _paymentToken Address of the ERC20 token used for payment.
     * @param _amount Amount of payment token to spend.
     */
    function buyTokensWithToken(
        address _paymentToken,
        uint256 _amount
    ) external {
        require(_amount > 0, "Payment must be > 0");
        uint256 price = adminContract.getPaymentTokenPrice(_paymentToken);
        require(price > 0, "Unsupported payment token");

        uint256 tokensToBuy = (_amount * 1e18) / price;
        require(tokensToBuy > 0, "Amount too small for 1 token");
        require(
            balanceOf(address(this)) >= tokensToBuy,
            "Not enough tokens in contract"
        );

        IERC20(_paymentToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        _transfer(address(this), msg.sender, tokensToBuy);
        emit TokensPurchased(msg.sender, tokensToBuy, _amount);
    }

    /**
     * @notice Allows users to sell tokens for BNB, using Chainlink for real-time pricing.
     * @param tokenAmount Amount of BEPEPE tokens to sell (in 18 decimals).
     */
    function sellTokensForBNB(uint256 tokenAmount) external {
        require(tokenAmount > 0, "Token amount must be > 0");
        (, int256 bnbUsdPrice, , , ) = bnbUsdPriceFeed.latestRoundData();
        require(bnbUsdPrice > 0, "Invalid price feed");

        uint256 usdValue18 = tokenAmount * TOKEN_PRICE_USD;
        uint256 bnbValue18 = (usdValue18 * 1e8) / uint256(bnbUsdPrice);
        uint256 bnbOwed = bnbValue18 / 1e18;
        require(bnbOwed > 0, "Too few tokens to swap");
        require(address(this).balance >= bnbOwed, "Not enough BNB in contract");

        _transfer(msg.sender, address(this), tokenAmount);
        payable(msg.sender).transfer(bnbOwed);
        emit TokensSwapped(msg.sender, tokenAmount, address(0), bnbOwed);
    }

    /**
     * @notice Allows users to sell tokens for an ERC20 token using a price from the admin contract.
     * @param _paymentToken Address of the ERC20 token to receive.
     * @param tokenAmount Amount of BEPEPE tokens to sell.
     */
    function sellTokensForToken(
        address _paymentToken,
        uint256 tokenAmount
    ) external {
        require(tokenAmount > 0, "Token amount must be > 0");
        uint256 price = adminContract.getPaymentTokenPrice(_paymentToken);
        require(price > 0, "Unsupported payment token");

        uint256 paymentAmount = (tokenAmount * price) / 1e18;
        require(paymentAmount > 0, "Too few tokens to swap");
        require(
            IERC20(_paymentToken).balanceOf(address(this)) >= paymentAmount,
            "Not enough payment token in contract"
        );

        _transfer(msg.sender, address(this), tokenAmount);
        IERC20(_paymentToken).safeTransfer(msg.sender, paymentAmount);
        emit TokensSwapped(
            msg.sender,
            tokenAmount,
            _paymentToken,
            paymentAmount
        );
    }

    /**
     * @notice Returns the token value in a specific ERC20 token for a given BEPEPE amount.
     * @param _paymentToken Address of the ERC20 token used for valuation.
     * @param bepepeAmount Amount of BEPEPE tokens.
     * @return Value in the payment token's smallest unit.
     */
    function getTokenValueForPaymentToken(
        address _paymentToken,
        uint256 bepepeAmount
    ) external view returns (uint256) {
        uint256 price = adminContract.getPaymentTokenPrice(_paymentToken);
        require(price > 0, "Unsupported payment token");
        return (bepepeAmount * price) / 1e18;
    }

    /**
     * @dev Optional function to mint additional tokens in the future.
     * This function is protected by the onlyOwner modifier.
     * @param to The address that will receive the newly minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Fallback function to accept BNB.
     */
    receive() external payable {}
}
