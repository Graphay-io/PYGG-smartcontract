import { ethers } from "hardhat";
import { PYGGportfolioRebalancer__factory } from "../typechain-types"; // Update this import to match your generated typechain path

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying the contract with the account:", deployer.address);

  // Define the addresses for the Uniswap V2 Router, Uniswap V3 Router, and Uniswap V3 Quoter on Polygon network
  const uniswapV2Router = "0xedf6066a2b290C185783862C7F4776A2C8077AD1";  // Replace with actual Uniswap V2 Router address
  const uniswapV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564";  // Replace with actual Uniswap V3 Router address
  const uniswapV3Quoter = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";  // Replace with actual Uniswap V3 Quoter address

  // Deploy the contract
  const PYGGportfolioRebalancerFactory = (await ethers.getContractFactory("PYGGportfolioRebalancer")) as PYGGportfolioRebalancer__factory;
  const pyggPortfolioRebalancer = await PYGGportfolioRebalancerFactory.deploy(uniswapV2Router, uniswapV3Router, uniswapV3Quoter);
  
  // await pyggPortfolioRebalancer.deployed();

  console.log("PYGGportfolioRebalancer deployed to:", await pyggPortfolioRebalancer.getAddress());

  // Define the data for bulkAddTokens
  const addresses = [
    "0xBbba073C31bF03b8ACf7c28EF0738DeCF3695683", 
    "0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39", 
    "0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4", 
    "0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a", 
    "0x2B9E7ccDF0F4e5B24757c1E1a80e311E34Cb10c7", 
    "0x430EF9263E76DAE63c84292C3409D61c598E9682", 
    "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", 
    "0xd93f7E271cB87c23AaA73edC008A79646d1F9912", 
    "0x2C89bbc92BD86F8075d1DEcc58C7F4E0107f286b", 
    "0x5fe2B58c013d7601147DcdD68C143A77499f5531", 
    "0x282d8efCe846A88B159800bd4130ad77443Fa1A1", 
    "0xbFc70507384047Aa74c29Cdc8c5Cb88D0f7213AC"
  ];

  const targetPercentages = [
    834, 834, 834, 834, 833, 833, 833, 833, 833, 833, 833, 833
  ];

  const versions = [
    "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3"
  ];

  const feeTiers = [
    3000, 500, 3000, 10000, 10000, 10000, 500, 3000, 3000, 3000, 3000, 10000
  ];

  // Call the bulkAddTokens function
  const tx = await pyggPortfolioRebalancer.bulkAddTokens(addresses, targetPercentages, versions, feeTiers);
  console.log("bulkAddTokens transaction sent, waiting for confirmation...", tx.hash);
  await tx.wait();
  console.log("Tokens added successfully to the portfolio.");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
