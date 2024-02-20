import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import { config as dotEnvConfig } from "dotenv";

dotEnvConfig();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false
    },
    localhost: {
      url: "http://127.0.0.1:8545", // same address and port for both Buidler and Ganache node
      accounts: [/* will be provided by ganache */],
      gas: 8000000,
      gasPrice: 1,
    },
    sepolia:{
      accounts:[`0x${process.env.PRIVATE_KEY}`],
      url: process.env.SEPOLIA_URL,
    },
    goerli: {
      accounts:[`0x${process.env.PRIVATE_KEY}`],
      url: process.env.GOERLI_URL,
      chainId: 5,
    },
    polygon:{
      accounts:[`0x${process.env.PRIVATE_KEY}`],
      url: process.env.POLYGON_URL
    },
    arbitrum:{
      accounts:[`0x${process.env.PRIVATE_KEY}`],
      url: process.env.ARBITRUM_URL
    }
  },
  etherscan: {
    apiKey: {
      sepolia: `${process.env.ETHERSCAN_API_KEY}`,
    },
  },
};

export default config;
