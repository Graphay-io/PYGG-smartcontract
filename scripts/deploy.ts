import { ethers, network } from "hardhat";
import { PYGGportfolioRebalancer__factory } from "../typechain-types"; // Update this import to match your generated typechain path

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying the contract with the account:", deployer.address);
  let uniswapV2Router;
  let uniswapV3Router;
  let uniswapV3Quoter;
  let addresses;
  let targetPercentages;
  let versions;
  let feeTiers;

  switch(network.name){
    case "polygon":
      uniswapV2Router = "0xedf6066a2b290C185783862C7F4776A2C8077AD1";  // Replace with actual Uniswap V2 Router address
      uniswapV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564";  // Replace with actual Uniswap V3 Router address
      uniswapV3Quoter = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";  // Replace with actual Uniswap V3 Quoter address
      addresses = [
        "0xBbba073C31bF03b8ACf7c28EF0738DeCF3695683", 
        "0xA3f751662e282E83EC3cBc387d225Ca56dD63D3A", 
        "0x430EF9263E76DAE63c84292C3409D61c598E9682", 
        "0xbFc70507384047Aa74c29Cdc8c5Cb88D0f7213AC", 
        "0xd0258a3fD00f38aa8090dfee343f10A9D4d30D3F",
        "0x2C89bbc92BD86F8075d1DEcc58C7F4E0107f286b",
        "0x61299774020dA444Af134c82fa83E3810b309991", 
        "0x282d8efCe846A88B159800bd4130ad77443Fa1A1"
      ];
      targetPercentages = [
        1250, 1250, 1250, 1250, 1250, 1250, 1250, 1250
      ]
      feeTiers = [
        3000, 100, 10000, 10000, 3000, 3000, 3000, 3000
      ]
      versions = [
        "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3"
      ]
      break;
    // case "bsc":
    //   uniswapV2Router = "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24";  // Replace with actual Uniswap V2 Router address
    //   uniswapV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564";  // Replace with actual Uniswap V3 Router address
    //   uniswapV3Quoter = "0x78D78E420Da98ad378D7799bE8f4AF69033EB077";  // Replace with actual Uniswap V3 Quoter address
    //   addresses = [
    //     "0xBbba073C31bF03b8ACf7c28EF0738DeCF3695683", 
    //     "0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39", 
    //     "0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4", 
    //     "0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a", 
    //     "0x2B9E7ccDF0F4e5B24757c1E1a80e311E34Cb10c7", 
    //     "0x430EF9263E76DAE63c84292C3409D61c598E9682", 
    //     "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", 
    //     "0xd93f7E271cB87c23AaA73edC008A79646d1F9912", 
    //     "0x2C89bbc92BD86F8075d1DEcc58C7F4E0107f286b", 
    //     "0x5fe2B58c013d7601147DcdD68C143A77499f5531", 
    //     "0x282d8efCe846A88B159800bd4130ad77443Fa1A1", 
    //     "0xbFc70507384047Aa74c29Cdc8c5Cb88D0f7213AC"
    //   ]
    //   targetPercentages = [
    //     834, 834, 834, 834, 833, 833, 833, 833, 833, 833, 833, 833
    //   ]
    //   feeTiers = [
    //     3000, 500, 3000, 10000, 10000, 10000, 500, 3000, 3000, 3000, 3000, 10000
    //   ]
    //   versions = [
    //     "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3"
    //   ]
    //   break;
    case "ethereum":
      uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";  // Replace with actual Uniswap V2 Router address
      uniswapV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564";  // Replace with actual Uniswap V3 Router address
      uniswapV3Quoter = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";  // Replace with actual Uniswap V3 Quoter address
      addresses = [
        "0xfd76be67fff3bac84e3d5444167bbc018f5968b6", 
        "0x325365ed8275f6a74cac98917b7f6face8da533b", 
        "0x824a30f2984f9013f2c8d0a29c0a3cc5fd5c0673",
        "0x465e56cd21ad47d4d4790f17de5e0458f20c3719",
        "0xe56c60b5f9f7b5fc70de0eb79c6ee7d00efa2625",
        "0xbaec0e18c770993ffb1175fef493b5113cc6e32d",
        "0x70cf99553471fe6c0d513ebfac8acc55ba02ab7b",
        "0x56ea002b411fd5887e55329852d5777ecb170713",
        "0x32121e0d11ecc79035045bc7466ede30816c5674",
        "0x0CfBeD8f2248D2735203f602BE0cAe5a3131ec68",
        "0xcaa004418eb42cdf00cb057b7c9e28f0ffd840a5",
        "0x70BB8E6844DFB681810FD557DD741bCaF027bF94",
        "0xbf85f94d3233ee588f0907a9147fbb59d7246b54",
        "0x4b5ab61593a2401b1075b90c04cbcdd3f87ce011",
        "0x7685cd3ddd862b8745b1082a6acb19e14eaa74f3",
        "0xe8b977aa5a9303fa94818441d78575e0f697ae72",
        "0x8c07e1dfede38b1908698988b4202a87e0d7a0f7",
        "0x98409d8ca9629fbe01ab1b914ebf304175e384c8",
        "0x86fef14c27c78deaeb4349fd959caa11fc5b5d75",
        "0x9572e4c0c7834f39b5b8dff95f211d79f92d7f23",
        "0x930b2c8ff1de619d4d6594da0ba03fdeda09a672",
        "0xcfb2e3fd46ba5e52af6bacbd63f0848696d674f3",
        "0xde5b7ff5b10cc5f8c95a2e2b643e3abf5179c987",
        "0x9cb91e5451d29c84b51ffd40df0b724b639bf841",
        "0xcd423f3ab39a11ff1d9208b7d37df56e902c932b",
        "0x515d459555f8c1fcf2791ded819b73b60a80b8e3",
      ]
      feeTiers = [
        10000, 10000, 3000, 3000, 0, 10000, 10000, 10000, 10000, 3000, 0, 3000, 3000, 3000, 3000, 10000, 0, 3000, 0, 10000, 0, 0,
        10000, 0
      ]
      targetPercentages = [
        385,
        385,
        385,
        385,
        385,
        385,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384,
        384
      ]
      versions = [
        "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3"
      ]
      break;
    case "arbitrum":      
      uniswapV2Router = "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24";  // Replace with actual Uniswap V2 Router address
      uniswapV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564";  // Replace with actual Uniswap V3 Router address
      uniswapV3Quoter = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";  // Replace with actual Uniswap V3 Quoter address
      addresses = [
        "0x9623063377AD1B27544C965cCd7342f7EA7e88C7", 
        "0xd4d42F0b6DEF4CE0383636770eF773390d85c61A"
      ]
      targetPercentages = [
        5000, 5000
      ]
      feeTiers = [
        3000, 0
      ]
      versions = [
        "v3", "v2"
      ]
      break;
    case "optimism":
      // uniswapV2Router = "0x4A7b5Da61326A6379179b40d00F57E5bbDC962c2";  // Replace with actual Uniswap V2 Router address
      // uniswapV3Router = "0xE592427A0AEce92De3Edee1F18E0157C05861564";  // Replace with actual Uniswap V3 Router address
      // uniswapV3Quoter = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";  // Replace with actual Uniswap V3 Quoter address
      // addresses = [
      //   "0xBbba073C31bF03b8ACf7c28EF0738DeCF3695683", 
      //   "0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39", 
      //   "0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4", 
      //   "0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a", 
      //   "0x2B9E7ccDF0F4e5B24757c1E1a80e311E34Cb10c7", 
      //   "0x430EF9263E76DAE63c84292C3409D61c598E9682", 
      //   "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", 
      //   "0xd93f7E271cB87c23AaA73edC008A79646d1F9912", 
      //   "0x2C89bbc92BD86F8075d1DEcc58C7F4E0107f286b", 
      //   "0x5fe2B58c013d7601147DcdD68C143A77499f5531", 
      //   "0x282d8efCe846A88B159800bd4130ad77443Fa1A1", 
      //   "0xbFc70507384047Aa74c29Cdc8c5Cb88D0f7213AC"
      // ]
      // targetPercentages = [
      //   834, 834, 834, 834, 833, 833, 833, 833, 833, 833, 833, 833
      // ]
      // feeTiers = [
      //   3000, 500, 3000, 10000, 10000, 10000, 500, 3000, 3000, 3000, 3000, 10000
      // ]
      // versions = [
      //   "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3", "v3"
      // ]
      // break;
    default:  
      throw new Error("The network not supported!!");
  }


  // Deploy the contract
  const PYGGportfolioRebalancerFactory = (await ethers.getContractFactory("PYGGportfolioRebalancer")) as PYGGportfolioRebalancer__factory;
  const pyggPortfolioRebalancer = await PYGGportfolioRebalancerFactory.deploy(uniswapV2Router, uniswapV3Router, uniswapV3Quoter);

  const deployedAddress =  await pyggPortfolioRebalancer.getAddress();
  console.log("PYGGportfolioRebalancer deployed to:", deployedAddress);

  // Define the data for bulkAddTokens

  // Call the bulkAddTokens function
  const gasEstimate = await deployer.provider.estimateGas({
    to: deployedAddress, // Address of the deployed contract
    data: pyggPortfolioRebalancer.interface.encodeFunctionData("bulkAddTokens", [
      addresses,
      targetPercentages,
      versions,
      feeTiers,
    ]),
  });

  const tx = await pyggPortfolioRebalancer.bulkAddTokens(addresses, targetPercentages, versions, feeTiers, {
    gasLimit: gasEstimate * 10000n
  });
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
