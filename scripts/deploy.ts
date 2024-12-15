import { ethers, network } from "hardhat";
import { PYGGportfolioRebalancer__factory } from "../typechain-types"; // Update this import to match your generated typechain path

async function main() {
  const [deployer] = await ethers.getSigners();
  const contractAddress = "0x3405011c05e35E9ba99746e69A3Cb282777031Bf"; // Deployed contract address

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
        "0xF57e7e7C23978C3cAEC3C3548E3D615c346e79fF", 
        "0x3506424F91fD33084466F402d5D97f05F8e3b4AF", 
        "0x5283D291DBCF85356A21bA090E6db59121208b44",
        "0xd1d2Eb1B1e90B638588728b4130137D262C87cae",
        "0xF629cBd94d3791C9250152BD8dfBDF380E2a3B9c",
        "0x767FE9EDC9E0dF98E07454847909b5E959D7ca0E",
        "0xb131f4A55907B10d1F0A50d8ab8FA09EC342cd74",
        "0x64Bc2cA1Be492bE7185FAA2c8835d9b824c8a194",
        "0xCC8Fa225D80b9c7D42F96e9570156c65D6cAAa25",
        "0x2a3bFF78B79A009976EeA096a51A948a3dC00e34",
        "0x8207c1FfC5B6804F6024322CcF34F29c3541Ae26",
        "0xA0Ef786Bf476fE0810408CaBA05E536aC800ff86",
        "0xf4d2888d29D722226FafA5d9B24F9164c092421E",
        "0xba5BDe662c17e2aDFF1075610382B9B691296350",
        "0xD13c7342e1ef687C5ad21b27c2b65D772cAb5C8c",
        "0x549020a9Cb845220D66d3E9c6D9F9eF61C981102",
        "0xF411903cbC70a74d22900a5DE66A2dda66507255",
        "0xFca59Cd816aB1eaD66534D82bc21E7515cE441CF",
        "0x34Be5b8C30eE4fDe069DC878989686aBE9884470",
        "0x87d73E916D7057945c9BcD8cdd94e42A6F47f776",
        "0x8A0a9b663693A22235B896f70a229C4A22597623",
        "0x07150e919B4De5fD6a63DE1F9384828396f25fDC"
      ]
      feeTiers = [
        10000,
        10000,
        3000,
        3000,
        0,
        10000,
        10000, 
        10000, 
        3000, 
        0, 
        3000, 
        3000, 
        3000, 
        3000, 
        10000,
        0, 
        3000, 
        0, 
        0, 
        10000, 
        0,
        0
      ]
      targetPercentages = [
        455,
        455,
        455,
        455,
        455,
        455,
        455,
        455,
        455,
        455,
        455,
        455,
        454,
        454,
        454,
        454,
        454,
        454,
        454,
        454,
        454,
        454
      ]
  versions = [
    "v3", 
    "v3", 
    "v3", 
    "v3", 
    "v2", 
    "v3", 
    "v3", 
    "v3", 
    "v3", 
    "v2", 
    "v3", 
  "v3", 
  "v3",
  "v3",
  "v3",
  "v2",
  "v3",
  "v2",
  "v2",
  "v3",
  "v2",
  "v2"
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


//   // Deploy the contract
  const PYGGportfolioRebalancerFactory = (await ethers.getContractFactory("PYGGportfolioRebalancer")) as PYGGportfolioRebalancer__factory;
  // const pyggPortfolioRebalancer = await PYGGportfolioRebalancerFactory.deploy(uniswapV2Router, uniswapV3Router, uniswapV3Quoter);

//   const deployedAddress =  await pyggPortfolioRebalancer.getAddress();
//   console.log("PYGGportfolioRebalancer deployed to:", deployedAddress);

//  // Estimate gas for contract deployment (before deployment)
//  const gasEstimate = await ethers.provider.estimateGas(
//   await PYGGportfolioRebalancerFactory.getDeployTransaction(
//     uniswapV2Router, 
//     uniswapV3Router, 
//     uniswapV3Quoter
//   )
// );


  // Define the data for bulkAddTokens

  // Call the bulkAddTokens function


  // const tx = await pyggPortfolioRebalancer.bulkAddTokens(addresses, targetPercentages, versions, feeTiers, {
  //   gasLimit: gasEstimate * 10000n
  // });
  // console.log("bulkAddTokens transaction sent, waiting for confirmation...", tx.hash);
  // await tx.wait();
  // console.log("Tokens added successfully to the portfolio.");

   // Attach to the deployed contract
   const pyggPortfolioRebalancer = PYGGportfolioRebalancer__factory.connect(contractAddress, deployer);

   // Estimate gas for the bulkAddTokens function
  //  const gasEstimate = await pyggPortfolioRebalancer.estimateGas.bulkAddTokens(
  //    addresses, targetPercentages, versions, feeTiers
  //  );
   const gasEstimate = await deployer.provider.estimateGas({
    to: contractAddress, // Address of the deployed contract
    data: pyggPortfolioRebalancer.interface.encodeFunctionData("bulkAddTokens", [
      addresses,
      targetPercentages,
      versions,
      feeTiers,
    ]),
  });
 
   // Call bulkAddTokens
   const tx = await pyggPortfolioRebalancer.bulkAddTokens(addresses, targetPercentages, versions, feeTiers, {
    gasLimit: gasEstimate * 10000n
   });
 
   console.log("bulkAddTokens transaction sent, waiting for confirmation...", tx.hash);
   await tx.wait();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
