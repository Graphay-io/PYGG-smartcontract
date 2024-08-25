import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
// import "@nomiclabs/hardhat-waffle";
import env from "dotenv";
env.config();

const config: HardhatUserConfig = {
  etherscan: {
    apiKey: "AHJFQN9UTSYFGA4BAYNDSG9QJ21W4X1WIT",
  },
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    // sepolia: {
    //   url: "https://sepolia.infura.io/v3/",
    //   accounts: ['0x']
    // },
    polygon: {
      url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.INFURA_API_KEY}`,
      chainId: 137,
      accounts: [`0x${process.env.DEPLOYMENT_ACCOUNT_KEY}`]
    },
  },
};


export default config;
