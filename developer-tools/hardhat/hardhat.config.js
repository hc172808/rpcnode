require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000001";
const GYDS_RPC    = process.env.GYDS_RPC    || "http://YOUR_RPC_NODE_IP";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },

  networks: {
    // GYDS Chain mainnet (Chain ID 13370)
    gyds: {
      url:      GYDS_RPC,
      chainId:  13370,
      accounts: [PRIVATE_KEY],
      gasPrice: 1_000_000_000, // 1 Gwei
    },

    // Local Hardhat node (for testing)
    localhost: {
      url:     "http://127.0.0.1:8545",
      chainId: 31337,
    },
  },

  // Named accounts for deploy scripts
  namedAccounts: {
    deployer: { default: 0 },
  },

  // Path overrides (optional)
  paths: {
    sources:   "./contracts",
    tests:     "./test",
    cache:     "./cache",
    artifacts: "./artifacts",
  },
};
