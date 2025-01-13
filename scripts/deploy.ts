const { ethers } = require("hardhat");
import { PYGGportfolioManagement__factory } from "../typechain-types"; // Update this import to match your generated typechain path

async function main() {
  const [deployer] = await ethers.getSigners();

  // Deploy mock Uniswap contracts
  const uniswapV2Router = "0xedf6066a2b290C185783862C7F4776A2C8077AD1"

  const uniswapV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564"

  const uniswapV3Quoter = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6"

  // Deploy PortfolioFactory contract
  const PortfolioFactory = await ethers.getContractFactory("PortfolioFactory");
  const portfolioFactory = await PortfolioFactory.deploy(uniswapV2Router, uniswapV3Router, uniswapV3Quoter);

  console.log("PortfolioFactory deployed to:", await portfolioFactory.getAddress());

  // Create a new portfolio
  const name = "DEFI";
  const symbol = "DEFI";
  const withdrawalFee = 100;
  const depositFee = 100;
  const tokens = ["0xA3f751662e282E83EC3cBc387d225Ca56dD63D3A"];
  const targetPercentages = [10000];

  const tx = await portfolioFactory.createPortfolio(name, symbol, withdrawalFee, depositFee, tokens, targetPercentages);
  await tx.wait();

  console.log("Portfolio created with name:", name);

  // Get the deployed portfolio address
  const portfolios = await portfolioFactory.getPortfolios(deployer.address);
  const portfolioAddress = portfolios[0].portfolioAddress;
  console.log("Portfolio address:", portfolioAddress);

  // Approve the portfolio to spend WETH tokens
  const WETH = await ethers.getContractAt("IERC20", "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270");
  const approveTx = await WETH.approve(portfolioAddress, ethers.utils.parseEther("10000000"));
  await approveTx.wait();

  console.log("Approved WETH for portfolio");

  // Deposit 0.001 WETH into the portfolio
  const PYGGportfolioManagement = await ethers.getContractAt("PYGGportfolioManagement", portfolioAddress);
  const depositTx = await PYGGportfolioManagement.deposit({
    amountIn: ethers.utils.parseEther("0.001"),
    version: 1, // Assuming Uniswap V2
    path: ["0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270000bb8a3f751662e282e83ec3cbc387d225ca56dd63d3a"]
  });
  await depositTx.wait();

  console.log("Deposited 0.001 WETH into the portfolio");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });