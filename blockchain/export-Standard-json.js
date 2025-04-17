// export-standard-json.js

const fs = require("fs");
const path = require("path");

// Helper to load a file’s contents
function loadSol(filePath) {
  return fs.readFileSync(path.resolve(__dirname, filePath), "utf8");
}

// === Adjust these paths if your layout differs ===
const sources = {
  // Your contracts
  "contracts/AdminBepepeToken.sol": loadSol("contracts/AdminBepepeToken.sol"),
  "contracts/UserBepepeToken.sol": loadSol("contracts/UserBepepeToken.sol"),
  "contracts/MockERC20.sol": loadSol("contracts/MockERC20.sol"),
  "contracts/MockAggregator.sol": loadSol("contracts/MockAggregator.sol"),

  // Your interfaces
  "contracts/interfaces/IBepepeAdmin.sol": loadSol(
    "contracts/interfaces/IBepepeAdmin.sol"
  ),
  "contracts/interfaces/AggregatorV3Interface.sol": loadSol(
    "contracts/interfaces/AggregatorV3Interface.sol"
  ),

  // OpenZeppelin contracts (from your node_modules)
  "@openzeppelin/contracts/access/Ownable.sol": loadSol(
    "node_modules/@openzeppelin/contracts/access/Ownable.sol"
  ),
  "@openzeppelin/contracts/token/ERC20/ERC20.sol": loadSol(
    "node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol"
  ),
  "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol": loadSol(
    "node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"
  ),
};

const input = {
  language: "Solidity",
  sources: Object.fromEntries(
    Object.entries(sources).map(([file, content]) => [file, { content }])
  ),
  settings: {
    optimizer: { enabled: false, runs: 200 }, // match your deploy settings
    evmVersion: "default",
    metadata: { useLiteralContent: true },
    outputSelection: {
      "*": {
        "*": ["abi", "evm.bytecode.object"],
      },
    },
  },
};

// Write the JSON to disk
const outPath = path.resolve(__dirname, "standard-json-input.json");
fs.writeFileSync(outPath, JSON.stringify(input, null, 2));
console.log("✅  Wrote standard-json-input.json to", outPath);
