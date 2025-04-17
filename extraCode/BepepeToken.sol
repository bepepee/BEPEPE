// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// If you want real-time BNB/USD, import the Chainlink aggregator interface:
import "./interfaces/AggregatorV3Interface.sol";

/**
 * @title BepepeToken
 * @notice An example token pegged at $7 with real-time BNB/USD price feeds,
 *         plus the ability to accept other ERC20s as payment. 
 *         This contract inherits from OpenZeppelin ERC20 and Ownable.
 */
contract BepepeToken is ERC20, Ownable {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------------
    // Configuration
    // ------------------------------------------------------------------------

    /// @dev Chainlink price feed for BNB/USD on BSC mainnet:
    ///      Mainnet BNB/USD = 0x0567F2323251f0AAb15c8DFb1967E4e8A7D42aeE
    ///      Testnet BNB/USD = 0x143db3CEEfbdfe5631aDD3E50f7614B6ba708BA7
    AggregatorV3Interface public bnbUsdPriceFeed;

    /// @dev We peg 1 BEPEPE = $7 (static).
    ///      Stored as 7 * 1e18 to keep 18 decimals. For example, 7.0 -> 7000000000000000000.
    uint256 public constant TOKEN_PRICE_USD = 7 * 1e18;

    /// @notice A mapping from ERC20 payment token => "cost to buy 1 BEPEPE"
    ///         (denominated in the smallest units of that payment token).
    ///         Example: If “1 token = 100 USDC” then you’d set paymentTokenPrices[USDC] = 100e6
    ///         (assuming USDC uses 6 decimals).
    mapping(address => uint256) public paymentTokenPrices;

    /// @dev Token logo URI or other metadata reference (IPFS/HTTPS).
    string public logoURI;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------
    event TokensPurchased(address indexed buyer, uint256 bepepeAmount, uint256 bnbOrTokenCost);
    event TokensSwapped(
        address indexed user,
        uint256 bepepeAmount,
        address paymentToken,
        uint256 paymentAmount
    );

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    
    /**
     * @dev Deploy the BEPEPE token with an initial supply minted to the deployer,
     *      sets the Chainlink BNB/USD aggregator, and sets an initial logo URI.
     * @param initialSupply  The number of tokens to mint at deployment (18 decimals).
     * @param priceFeedAddr  The Chainlink aggregator address for BNB/USD (mainnet or testnet).
     * @param initialLogoURI The initial URI for the token’s logo.
     */
    constructor(
        uint256 initialSupply,
        address priceFeedAddr,
        string memory initialLogoURI
    ) ERC20("BEPEPE", "PEPE") {
        require(priceFeedAddr != address(0), "Invalid price feed address");
        bnbUsdPriceFeed = AggregatorV3Interface(priceFeedAddr);

        // Mint the initial supply to the deployer (owner).
        _mint(msg.sender, initialSupply);

        // Optionally set a logo or other metadata URI.
        logoURI = initialLogoURI;
    }

    // ------------------------------------------------------------------------
    // Owner-only Functions
    // ------------------------------------------------------------------------

    /**
     * @notice Allows the contract owner to update the logo URI.
     * @param newLogoURI The new logo URI (e.g. IPFS or HTTPS URL).
     */
    function setLogoURI(string memory newLogoURI) external onlyOwner {
        logoURI = newLogoURI;
    }

    /**
     * @notice The owner can mint new BEPEPE tokens.
     * @param to     The recipient of the minted tokens.
     * @param amount The amount to mint (in 18 decimals).
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice The owner can burn tokens from any address (if needed).
     * @param from   The address whose tokens are to be burned.
     * @param amount The amount of tokens to burn (in 18 decimals).
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /**
     * @notice The owner can deposit tokens into the contract’s balance
     *         (making them available for users to buy).
     * @param amount The amount of tokens to deposit (18 decimals).
     */
    function depositTokens(uint256 amount) external onlyOwner {
        _transfer(msg.sender, address(this), amount);
    }

    /**
     * @notice The owner can set the price ratio for an accepted ERC20 token.
     *         For instance, if 1 BEPEPE = 100 units of an ERC20 stablecoin,
     *         then pass in 100*(10^tokenDecimals).
     * @param _paymentToken The ERC20 token address used for payment.
     * @param _price        The units of that token per 1 BEPEPE (with the token’s decimals).
     */
    function setPaymentTokenPrice(address _paymentToken, uint256 _price) external onlyOwner {
        require(_paymentToken != address(0), "Invalid token address");
        paymentTokenPrices[_paymentToken] = _price;
    }

    /**
     * @notice Withdraws specific ERC20 tokens from the contract’s balance.
     * @param _paymentToken The ERC20 token address to withdraw.
     * @param amount        The amount to withdraw.
     */
    function withdrawPaymentToken(address _paymentToken, uint256 amount) external onlyOwner {
        require(_paymentToken != address(0), "Invalid token address");
        IERC20(_paymentToken).safeTransfer(owner(), amount);
    }

    /**
     * @notice Withdraws all BNB from the contract.
     */
    function withdrawBNB() external onlyOwner {
        uint256 bnbBalance = address(this).balance;
        require(bnbBalance > 0, "No BNB to withdraw");
        payable(owner()).transfer(bnbBalance);
    }

    // ------------------------------------------------------------------------
    // Public/User Functions
    // ------------------------------------------------------------------------

    /**
     * @notice Buy BEPEPE tokens with BNB, using real-time BNB/USD from Chainlink,
     *         pegging BEPEPE at a static $7 each.
     */
    function buyTokens() external payable {
        // Must send some BNB
        require(msg.value > 0, "BNB amount is zero");

        // 1) Get the latest BNB/USD price from Chainlink (8 decimals).
        (, int256 bnbUsdPrice, , , ) = bnbUsdPriceFeed.latestRoundData();
        require(bnbUsdPrice > 0, "Invalid chainlink price");
        uint256 bnbPrice = uint256(bnbUsdPrice); // e.g., 300_00000000 if 1 BNB=$300

        // 2) Convert the incoming BNB (msg.value) into “USD” at 18 decimals.
        //    - msg.value is in wei (1 BNB = 1e18 wei).
        //    - bnbPrice is in 8 decimals, so multiply msg.value * bnbPrice -> 1e18 * 1e8 = 1e26
        //      then divide by 1e8 to bring it back to 1e18 => effectively a “USD * 1e18” result.
        uint256 bnbValueInUsd18 = (msg.value * bnbPrice) / 1e8;

        // 3) Since we have pegged 1 BEPEPE = 7 * 1e18 “USD units,”
        //    the number of tokens is (bnbValueInUsd18 / TOKEN_PRICE_USD).
        //    Both are in 1e18, so final tokensToBuy is also scaled up by 1e18, as usual for ERC20.
        uint256 tokensToBuy = bnbValueInUsd18 / TOKEN_PRICE_USD;
        require(tokensToBuy > 0, "Insufficient BNB for 1 token");

        // 4) Make sure the contract has enough BEPEPE available for sale.
        require(balanceOf(address(this)) >= tokensToBuy, "Insufficient tokens in contract");

        // 5) Transfer the tokens out to the buyer.
        _transfer(address(this), msg.sender, tokensToBuy);

        emit TokensPurchased(msg.sender, tokensToBuy, msg.value);
    }

    /**
     * @notice Buy BEPEPE tokens using an accepted ERC20 token.
     *         Price is set manually by the owner via `setPaymentTokenPrice()`.
     * @param _paymentToken The ERC20 token used for payment.
     * @param _amount       The amount of that token to spend.
     */
    function buyTokensWithToken(address _paymentToken, uint256 _amount) external {
        uint256 price = paymentTokenPrices[_paymentToken];
        require(price > 0, "This payment token is not accepted");
        require(_amount > 0, "Payment amount must be greater than zero");

        // Number of BEPEPE to buy = (_amount * 1 BEPEPE) / (price).
        // The “price” is how many units of _paymentToken are needed per 1 BEPEPE.
        uint256 tokensToBuy = (_amount * 1e18) / price; 
        require(tokensToBuy > 0, "Payment too low for 1 token");
        require(balanceOf(address(this)) >= tokensToBuy, "Insufficient tokens in contract");

        // Transfer payment from user -> this contract
        IERC20(_paymentToken).safeTransferFrom(msg.sender, address(this), _amount);

        // Then transfer purchased BEPEPE out to user
        _transfer(address(this), msg.sender, tokensToBuy);

        emit TokensPurchased(msg.sender, tokensToBuy, _amount);
    }

    /**
     * @notice Sell BEPEPE tokens for BNB, pegged at $7 each, while
     *         BNB/USD is determined in real time via Chainlink.
     * @param tokenAmount The amount of BEPEPE tokens to sell (18 decimals).
     */
    function sellTokensForBNB(uint256 tokenAmount) external {
        require(tokenAmount > 0, "Token amount must be greater than zero");

        // 1) Convert “how much USD” we are selling = tokenAmount * $7
        //    For 18 decimals, tokenAmount is 1e18 based, TOKEN_PRICE_USD is also 1e18 based,
        //    so the product is 1e36. We’ll keep it as 1e36 for a moment.
        uint256 usdValue18 = tokenAmount * TOKEN_PRICE_USD; // 1e36

        // 2) Get the latest BNB/USD from Chainlink (8 decimals).
        (, int256 bnbUsdPrice, , , ) = bnbUsdPriceFeed.latestRoundData();
        require(bnbUsdPrice > 0, "Invalid chainlink price");
        uint256 bnbPrice = uint256(bnbUsdPrice); // e.g. 300_00000000 for $300

        // 3) Convert that “usdValue18” into BNB. 
        //    - We have to invert the formula from buyTokens:
        //      bnbValueInUsd18 = (bnb * bnbPrice) / 1e8
        //    => bnb = (bnbValueInUsd18 * 1e8) / bnbPrice
        //    Here, “bnbValueInUsd18” is “usdValue18,” but watch decimals carefully:
        //      usdValue18 is 1e36, bnbPrice is 1e8, we multiply by 1e8 => 1e44,
        //      then divide by bnbPrice (1e8) => 1e36 again, but BNB in 1e18. 
        //    Finally we must also / 1e18 to correct for the fact that the “usdValue18”
        //    is scaled by 1e18. Let’s do it step by step to keep clarity:
        uint256 bnbValue18 = (usdValue18 * 1e8) / bnbPrice; // yields 1e44 / 1e8 = 1e36
        // We must correct for the extra 1e18 factor from “usdValue18”. So:
        uint256 bnbOwed = bnbValue18 / 1e18; // => 1e36 / 1e18 = 1e18, i.e. BNB in wei.

        require(bnbOwed > 0, "Token amount too small for swap");
        require(address(this).balance >= bnbOwed, "Insufficient BNB in contract");

        // 4) Transfer tokens from user -> contract
        _transfer(msg.sender, address(this), tokenAmount);

        // 5) Send BNB to user
        payable(msg.sender).transfer(bnbOwed);

        emit TokensSwapped(msg.sender, tokenAmount, address(0), bnbOwed);
    }

    /**
     * @notice Sell BEPEPE tokens for an accepted ERC20 token,
     *         based on the price set by `setPaymentTokenPrice()`.
     * @param _paymentToken The ERC20 token that the seller wants to receive.
     * @param tokenAmount   The amount of BEPEPE to sell.
     */
    function sellTokensForToken(address _paymentToken, uint256 tokenAmount) external {
        uint256 price = paymentTokenPrices[_paymentToken];
        require(price > 0, "This payment token is not accepted");
        require(tokenAmount > 0, "Token amount must be greater than zero");

        // Payment owed = (tokenAmount * price) / 1e18
        // Because “price” is how many units (w/ its decimals) are needed per 1 BEPEPE,
        // and tokenAmount is 1e18 based. 
        uint256 paymentAmount = (tokenAmount * price) / 1e18;
        require(paymentAmount > 0, "Token amount too small for swap");
        require(
            IERC20(_paymentToken).balanceOf(address(this)) >= paymentAmount,
            "Insufficient payment tokens in contract"
        );

        // Transfer BEPEPE from user -> contract
        _transfer(msg.sender, address(this), tokenAmount);

        // Transfer the payment tokens to user
        IERC20(_paymentToken).safeTransfer(msg.sender, paymentAmount);

        emit TokensSwapped(msg.sender, tokenAmount, _paymentToken, paymentAmount);
    }

    /**
     * @notice Helper function to see “how many units of _paymentToken” correspond
     *         to a certain amount of BEPEPE. This does NOT handle real-time BNB, 
     *         just the manually set paymentTokenPrices for stablecoins, etc.
     * @param _paymentToken The ERC20 token used for valuation.
     * @param bepepeAmount  The amount of BEPEPE for which we want the price.
     * @return priceInToken The payment token units owed for that many BEPEPE.
     */
    function getTokenValueForPaymentToken(
        address _paymentToken,
        uint256 bepepeAmount
    ) external view returns (uint256) {
        uint256 price = paymentTokenPrices[_paymentToken];
        require(price > 0, "This payment token is not accepted");
        return (bepepeAmount * price) / 1e18;
    }

    /**
     * @notice Fallback to accept BNB.
     */
    receive() external payable {}
}
