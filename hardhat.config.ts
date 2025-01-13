import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import env from "dotenv";
env.config();

const config: HardhatUserConfig = {
  etherscan: {
    apiKey: "-", // polygon
    // apiKey: "YB3X78F14NZV8YW6RHTW74GC9XXZZFHZJS", // arbitrum
  },
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  
  networks: {
    hardhat: {
      forking: {
        url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.INFURA_API_KEY}`,
        blockNumber: 66605908
      }
    },
    polygon: {
      url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.INFURA_API_KEY}`,
      chainId: 137,
      accounts: [`0x${process.env.DEPLOYMENT_ACCOUNT_KEY}`]
    },
    arbitrum: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.INFURA_API_KEY}`,
      chainId: 42161,
      accounts: [`0x${process.env.DEPLOYMENT_ACCOUNT_KEY}`]
    },
    ethereum: {
      url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.INFURA_API_KEY}`,
      chainId: 1,
      accounts: [`0x${process.env.DEPLOYMENT_ACCOUNT_KEY}`]
    },
    bsc: {
      url: `https://bsc-mainnet.g.alchemy.com/v2/${process.env.INFURA_API_KEY}`,
      chainId: 56,
      accounts: [`0x${process.env.DEPLOYMENT_ACCOUNT_KEY}`]
    },
    optimism: {
      url: `https://opt-mainnet.g.alchemy.com/v2/${process.env.INFURA_API_KEY}`,
      chainId: 10,
      accounts: [`0x${process.env.DEPLOYMENT_ACCOUNT_KEY}`]
    },
  },
};


export default config;
