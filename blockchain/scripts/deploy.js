const { ethers, network, run } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying BEPEPE Token with account:", deployer.address);
  console.log("Network:", network.name);

  // Check deployer's BNB balance.
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Deployer balance (wei):", balance.toString());

  // BNB/USD aggregator address on BSC mainnet.
  const bnbUsdPriceFeedMainnet = ethers.getAddress(
    "0x0567f2323251f0aab15c8dfb1967e4e8a7d42aee"
  );

  // Define the initial supply for the UserBepepeToken.
  const initialSupply = ethers.parseUnits("100000000000000000000000000", 18);

  // Example logo URI (could be IPFS).
  const initialLogoURI =
    "https://gateway.pinata.cloud/ipfs/bafybeid3wqouzz3hq274gztj3fhfbtbwpulldsrprkc6oilupwtbmk75t4";

  // 1) Deploy the Admin contract.
  const AdminTokenFactory = await ethers.getContractFactory("AdminBepepeToken");
  const adminContract = await AdminTokenFactory.deploy();
  await adminContract.waitForDeployment();
  const adminAddress = await adminContract.getAddress();
  console.log("AdminBepepeToken deployed at:", adminAddress);

  // 2) Deploy the User-facing token contract.
  const UserTokenFactory = await ethers.getContractFactory("UserBepepeToken");
  const userToken = await UserTokenFactory.deploy(
    initialSupply,
    bnbUsdPriceFeedMainnet,
    initialLogoURI,
    adminAddress
  );
  await userToken.waitForDeployment();
  const userAddress = await userToken.getAddress();
  console.log("UserBepepeToken deployed at:", userAddress);

  // 3) Verify Admin contract (no constructor args)
  console.log("Verifying AdminBepepeToken on BscScan...");
  await run("verify:verify", {
    address: adminAddress,
    constructorArguments: [],
  });

  // 4) Verify UserBepepeToken with its constructor args
  console.log("Verifying UserBepepeToken on BscScan...");
  await run("verify:verify", {
    address: userAddress,
    constructorArguments: [
      initialSupply,
      bnbUsdPriceFeedMainnet,
      initialLogoURI,
      adminAddress,
    ],
  });

  console.log("✅ Deployment and verification complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error in deploy-and-verify:", error);
    process.exit(1);
  });
