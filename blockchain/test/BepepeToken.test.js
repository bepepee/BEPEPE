// test/BepepeToken.test.js:
const { expect } = require("chai");
const { ethers } = require("hardhat");

const ZERO = "0x0000000000000000000000000000000000000000";

describe("UserBepepeToken", function () {
  let userToken, adminContract, paymentToken, mockAggregator;
  let owner, addr1, addr2;

  // Full initial supply to be minted (for example, 1e26 tokens scaled by 18 decimals)
  const initialSupply = ethers.parseUnits("100000000000000000000000000", 18);
  // Sale pool: allocate 10% of the full supply to the token contract for sale
  const salePoolTokens = initialSupply / 10n;
  const initialLogoURI =
    "https://gateway.pinata.cloud/ipfs/bafybeid3wqouzz3hq274gztj3fhfbtbwpulldsrprkc6oilupwtbmk75t4";
  // Our mock aggregator will simulate a BNB price of $300 (with 8 decimals: 300 * 10^8).
  const mockPrice = "30000000000";

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy the Mock Aggregator.
    const MockAggregatorFactory = await ethers.getContractFactory(
      "MockAggregator"
    );
    mockAggregator = await MockAggregatorFactory.deploy(mockPrice);
    await mockAggregator.waitForDeployment();

    // Deploy the Admin contract.
    const AdminFactory = await ethers.getContractFactory("AdminBepepeToken");
    adminContract = await AdminFactory.deploy();
    await adminContract.waitForDeployment();

    // Deploy the Payment Token (MockERC20).
    const PaymentTokenFactory = await ethers.getContractFactory("MockERC20");
    paymentToken = await PaymentTokenFactory.deploy(
      "Mock Payment Token",
      "MPT",
      ethers.parseUnits("1000000", 18)
    );
    await paymentToken.waitForDeployment();

    // Set the payment token price in the admin contract: 1 BEPEPE = 100 MPT.
    await adminContract.setPaymentTokenPrice(
      await paymentToken.getAddress(),
      ethers.parseUnits("100", 18)
    );

    // Deploy the UserBepepeToken contract.
    // Note: The entire supply is minted to the deployer (owner) in this new design.
    const UserTokenFactory = await ethers.getContractFactory("UserBepepeToken");
    userToken = await UserTokenFactory.deploy(
      initialSupply,
      await mockAggregator.getAddress(),
      initialLogoURI,
      await adminContract.getAddress()
    );
    await userToken.waitForDeployment();

    // Allocate tokens for sale: transfer salePoolTokens from owner to the token contract.
    await userToken.transfer(await userToken.getAddress(), salePoolTokens);

    // Transfer some payment tokens to test accounts.
    await paymentToken.transfer(addr1.address, ethers.parseUnits("10000", 18));
    await paymentToken.transfer(addr2.address, ethers.parseUnits("10000", 18));

    // Fund the token contract with 2 ETH for its sell functions.
    await owner.sendTransaction({
      to: await userToken.getAddress(),
      value: ethers.parseUnits("2", "ether"),
    });
  });

  it("should have correct name, symbol, and decimals", async function () {
    expect(await userToken.name()).to.equal("BEPEPE");
    expect(await userToken.symbol()).to.equal("PEPE");
    expect(await userToken.decimals()).to.equal(18);
  });

  it("should have initial supply allocated correctly", async function () {
    // Owner's balance should be initialSupply minus salePoolTokens.
    const ownerBalance = await userToken.balanceOf(owner.address);
    expect(ownerBalance).to.equal(initialSupply - salePoolTokens);
    // Token contract's balance should be equal to salePoolTokens.
    const contractBalance = await userToken.balanceOf(
      await userToken.getAddress()
    );
    expect(contractBalance).to.equal(salePoolTokens);
  });

  it("should allow users to buy tokens with BNB", async function () {
    const buyAmountBNB = ethers.parseUnits("0.03", "ether");
    const initialBalance = await userToken.balanceOf(addr1.address);
    await userToken.connect(addr1).buyTokens({ value: buyAmountBNB });
    const newBalance = await userToken.balanceOf(addr1.address);
    expect(newBalance).to.be.gt(initialBalance);
  });

  it("should revert when buying tokens with zero BNB", async function () {
    await expect(
      userToken.connect(addr1).buyTokens({ value: 0 })
    ).to.be.revertedWith("No BNB sent");
  });

  it("should allow users to buy tokens with an ERC20 token", async function () {
    const paymentAmount = ethers.parseUnits("200", 18);
    await paymentToken
      .connect(addr1)
      .approve(await userToken.getAddress(), paymentAmount);
    await userToken
      .connect(addr1)
      .buyTokensWithToken(await paymentToken.getAddress(), paymentAmount);
    // With payment token price set to 100 (scaled by 1e18), 200 tokens paid gives 2 BEPEPE tokens.
    expect(await userToken.balanceOf(addr1.address)).to.equal(
      ethers.parseUnits("2", 18)
    );
  });

  it("should revert when buying tokens with an unsupported ERC20", async function () {
    await expect(
      userToken
        .connect(addr1)
        .buyTokensWithToken(ZERO, ethers.parseUnits("100", 18))
    ).to.be.revertedWith("Unsupported payment token");
  });

  it("should allow users to sell tokens for BNB", async function () {
    // First, have addr1 buy tokens with BNB.
    const buyAmountBNB = ethers.parseUnits("2", "ether");
    await userToken.connect(addr1).buyTokens({ value: buyAmountBNB });
    const tokensBought = await userToken.balanceOf(addr1.address);
    expect(tokensBought).to.be.gt(0);

    const balanceBefore = await ethers.provider.getBalance(addr1.address);
    const sellTx = await userToken
      .connect(addr1)
      .sellTokensForBNB(tokensBought);
    const sellReceipt = await sellTx.wait();

    // Manually decode the TokensSwapped event.
    const tokensSwappedTopic = ethers.id(
      "TokensSwapped(address,uint256,address,uint256)"
    );
    const log = sellReceipt.logs.find(
      (log) => log.topics[0] === tokensSwappedTopic
    );
    const parsedEvent = userToken.interface.parseLog(log);
    const bnbOwed = BigInt(parsedEvent.args.paymentAmount.toString());

    // Calculate gas cost.
    const gasUsed = BigInt(sellReceipt.gasUsed.toString());
    const effectiveGasPrice = sellReceipt.effectiveGasPrice
      ? BigInt(sellReceipt.effectiveGasPrice.toString())
      : BigInt((await sellTx.gasPrice).toString());
    const gasCost = gasUsed * effectiveGasPrice;

    const balanceAfter = BigInt(
      (await ethers.provider.getBalance(addr1.address)).toString()
    );
    const balanceBeforeBigInt = BigInt(balanceBefore.toString());
    const computed = balanceAfter + gasCost;
    const expectedVal = balanceBeforeBigInt + bnbOwed;

    // Allow a small tolerance.
    const tolerance = BigInt(ethers.parseUnits("0.001", "ether").toString());
    const diff =
      computed >= expectedVal ? computed - expectedVal : expectedVal - computed;
    expect(diff).to.be.lessThan(tolerance);
  });

  it("should revert when selling tokens for BNB with zero token amount", async function () {
    await expect(
      userToken.connect(addr1).sellTokensForBNB(0)
    ).to.be.revertedWith("Token amount must be > 0");
  });

  it("should allow users to sell tokens for an ERC20 token", async function () {
    const paymentAmount = ethers.parseUnits("200", 18);
    await paymentToken
      .connect(addr1)
      .approve(await userToken.getAddress(), paymentAmount);
    await userToken
      .connect(addr1)
      .buyTokensWithToken(await paymentToken.getAddress(), paymentAmount);
    expect(await userToken.balanceOf(addr1.address)).to.equal(
      ethers.parseUnits("2", 18)
    );

    await paymentToken.transfer(
      await userToken.getAddress(),
      ethers.parseUnits("1000", 18)
    );
    await userToken
      .connect(addr1)
      .sellTokensForToken(
        await paymentToken.getAddress(),
        ethers.parseUnits("1", 18)
      );
    expect(await paymentToken.balanceOf(addr1.address)).to.equal(
      ethers.parseUnits("9900", 18)
    );
  });

  it("should revert when selling tokens for an unsupported ERC20", async function () {
    await expect(
      userToken
        .connect(addr1)
        .sellTokensForToken(ZERO, ethers.parseUnits("1", 18))
    ).to.be.revertedWith("Unsupported payment token");
  });

  it("should accept BNB via fallback", async function () {
    const initialBNBBalance = BigInt(
      (
        await ethers.provider.getBalance(await userToken.getAddress())
      ).toString()
    );
    const sendAmount = ethers.parseUnits("0.005", "ether");
    await owner.sendTransaction({
      to: await userToken.getAddress(),
      value: sendAmount,
    });
    const newBNBBalance = BigInt(
      (
        await ethers.provider.getBalance(await userToken.getAddress())
      ).toString()
    );
    expect(newBNBBalance - initialBNBBalance).to.equal(
      BigInt(sendAmount.toString())
    );
  });
});
