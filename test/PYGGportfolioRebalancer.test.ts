import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { defaultAbiCoder } from "@ethersproject/abi";
import { Contract, ContractFactory, Signer } from "ethers";
import { PortfolioFactory } from "../typechain-types";
import UniswapV2Factory from "@uniswap/v2-core/build/UniswapV2Factory.json";
import UniswapV2Router02 from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import IUniswapV2Pair from "@uniswap/v2-periphery/build/IUniswapV2Pair.json";

describe("PYGGportfolioManagement", function () {
  let PortfolioFactory: PortfolioFactory;
  let PYGGportfolioManagement: Contract;
  let MockUniswapV3Router: Contract;
  let MockUniswapV3Quoter: Contract;
  let WETH: Contract;
  let TSTToken: Contract;
  let owner: Signer;
  let liquidityProvider: Signer;

  beforeEach(async function () {
    [owner, liquidityProvider] = await ethers.getSigners();

    // Deploy mock Uniswap contracts
    const uniswapV2Factory = new ContractFactory(
      UniswapV2Factory.abi,
      UniswapV2Factory.bytecode,
      liquidityProvider)
    const factory = (await uniswapV2Factory.connect(liquidityProvider).deploy(await owner.getAddress())) as unknown as Contract;
    
    // Deploy TEST token
    const MockTESTFactory = await ethers.getContractFactory("MockTESTToken");
    TSTToken = await MockTESTFactory.connect(liquidityProvider).deploy("test token 1", "TST") as unknown as Contract;

    // Deploy WETH token
    const WETHFactory = await ethers.getContractFactory("MockWETH");
    WETH = await WETHFactory.connect(liquidityProvider).deploy() as unknown as Contract;

    const txCreatePair = await factory.createPair(TSTToken, WETH);
    txCreatePair.wait();

    const pairAddress = await factory.getPair(TSTToken, WETH);
    const pair = new Contract(pairAddress, IUniswapV2Pair.abi, owner);
    
    // Deploy UniswapV2Router contract
    const UniswapV2Router = await ethers.getContractFactory(
      UniswapV2Router02.abi,
      UniswapV2Router02.bytecode
    );
    const router = await UniswapV2Router.connect(liquidityProvider).deploy(await factory.getAddress(), await WETH.getAddress()) as unknown as Contract;
    const routerAddress = await router.getAddress();

    const MaxUint256 =
    "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

    const approveTx1 = await TSTToken.approve(routerAddress, MaxUint256);
    await approveTx1.wait();
    const approvalTx2 = await WETH.approve(routerAddress, MaxUint256);
    await approvalTx2.wait();

    const token0Amount = ethers.parseUnits("100");
    const token1Amount = ethers.parseUnits("100");

    const lpTokenBalanceBefore = await pair.balanceOf(await owner.getAddress());
    const deadline = Math.floor(Date.now() / 1000) + 10 * 60;

    const addLiquidityTx = await router
    .addLiquidity(
      await TSTToken.getAddress(),
      await WETH.getAddress(),
      token0Amount,
      token1Amount,
      0,
      0,
      owner,
      deadline
    );
    await addLiquidityTx.wait();

    // Deploy mock UniswapV3 contracts
    const MockUniswapV3RouterFactory = await ethers.getContractFactory("MockUniswapV3Router");
    MockUniswapV3Router = await MockUniswapV3RouterFactory.deploy() as unknown as Contract;

    // Deploy mock UniswapV3Quoter contract
    const MockUniswapV3QuoterFactory = await ethers.getContractFactory("MockUniswapV3Quoter");
    MockUniswapV3Quoter = await MockUniswapV3QuoterFactory.deploy() as unknown as Contract;

    // Deploy PortfolioFactory contract
    const PortfolioFactoryFactory = await ethers.getContractFactory("PortfolioFactory");
    PortfolioFactory = await PortfolioFactoryFactory.deploy(await router.getAddress(), await MockUniswapV3Router.getAddress(), await MockUniswapV3Quoter.getAddress()) as PortfolioFactory;
    const TSTTokenAddr = await TSTToken.getAddress();
  
    (WETH as any).connect(liquidityProvider).transfer(await owner.getAddress(), ethers.parseEther("10"));
    let reserve = await pair.getReserves();

    // Create a new portfolio
    const name = "DEFI";
    const symbol = "DEFI";
    const withdrawalFee = 100;
    const depositFee = 100;
    const tokens = [TSTTokenAddr];
    const targetPercentages = [10000];
    const tx = await PortfolioFactory.connect(owner).createPortfolio(name, symbol, withdrawalFee, depositFee, tokens, targetPercentages);
    await tx.wait();

    // Get the deployed portfolio address
    const portfolios = await PortfolioFactory.connect(owner).getPortfolios(await owner.getAddress());
    const portfolioAddress = portfolios[0].portfolioAddress;

    // Get the deployed PYGGportfolioManagement contract
    PYGGportfolioManagement = await ethers.getContractAt("PYGGportfolioManagement", portfolioAddress) as unknown as Contract;
    await PYGGportfolioManagement.setSlippageTolerance(500);
  });

  describe("Initialization", function () {
    it("Should initialize the portfolio with the correct values", async function () {
      const name = await PYGGportfolioManagement.name();
      const symbol = await PYGGportfolioManagement.symbol();
      const withdrawalFee = await PYGGportfolioManagement.withdrawalFee();
      const depositFee = await PYGGportfolioManagement.depositFee();
      const tokens = await PYGGportfolioManagement.getBasket();

      expect(name).to.equal("DEFI");
      expect(symbol).to.equal("DEFI");
      expect(withdrawalFee).to.equal(100);
      expect(depositFee).to.equal(100);
      expect(tokens.length).to.equal(1);
      expect(tokens[0].token).to.equal(await TSTToken.getAddress());
      expect(tokens[0].targetPercentage).to.equal(10000);
    });
  });

  describe("Deposit", function () {
    it("Should allow deposit of WETH", async function () {
      const amountIn = ethers.parseEther("10");

      // Approve the portfolio to spend WETH tokens
      await (WETH as any).connect(owner).approve(await PYGGportfolioManagement.getAddress(), amountIn);
      const wethAddress = await WETH.getAddress();
      const tstTokenAddress = await TSTToken.getAddress();

      // Deposit WETH into the portfolio
      const depositTx = await PYGGportfolioManagement.deposit({
        directions: [
          {
            path: defaultAbiCoder.encode(["address[]"], [[wethAddress, tstTokenAddress]]),
            version: 0 // Assuming Uniswap V2
          }
        ],
        amountIn: amountIn,
      });
      await depositTx.wait();

      const balance = await PYGGportfolioManagement.balanceOf(await owner.getAddress());
      expect(balance).to.equal(BigNumber.from(amountIn).mul(9900).div(10000)); // 1% deposit fee
    });
  });

  describe("Withdraw", function () {
    it("Should allow withdrawal of WETH", async function () {
      const amountIn = ethers.parseEther("10");

      // Approve the portfolio to spend WETH tokens
      await (WETH as any).connect(owner).approve(await PYGGportfolioManagement.getAddress(), amountIn);

      // Deposit WETH into the portfolio
      const depositTx = await PYGGportfolioManagement.deposit({
        amountIn: amountIn,
        directions: [
          {
            path: defaultAbiCoder.encode(["address[]"], [[await WETH.getAddress(), await TSTToken.getAddress()]]),
            version: 0 // Assuming Uniswap V2
          }
        ]
      });
      await depositTx.wait();

      const balancePYYGTokenBefore = BigNumber.from(await PYGGportfolioManagement.balanceOf(await owner.getAddress()));

      // Withdraw WETH from the portfolio
      const withdrawTx = await PYGGportfolioManagement.withdrawToETH(balancePYYGTokenBefore.toBigInt(), {
        amountIn: amountIn,
        directions: [
          {
            path: defaultAbiCoder.encode(["address[]"], [[await TSTToken.getAddress(), await WETH.getAddress()]]),
            version: 0 // Assuming Uniswap V2
          }
        ]
      });
      await withdrawTx.wait();
      
      const balancePYYGShareTokenAfter = BigNumber.from(await PYGGportfolioManagement.balanceOf(await owner.getAddress()));

      expect(balancePYYGTokenBefore.sub(balancePYYGShareTokenAfter)).to.equal(balancePYYGTokenBefore); // Give whole ShareToken back
    });

    it("Should allow withdrawal in kind portfolio", async function () {
      const amountIn = ethers.parseEther("10");

      // Approve the portfolio to spend WETH tokens
      await (WETH as any).connect(owner).approve(await PYGGportfolioManagement.getAddress(), amountIn);

      // Deposit WETH into the portfolio
      const depositTx = await PYGGportfolioManagement.deposit({
        amountIn: amountIn,
        directions: [
          {
            path: defaultAbiCoder.encode(["address[]"], [[await WETH.getAddress(), await TSTToken.getAddress()]]),
            version: 0 // Assuming Uniswap V2
          }
        ]
      });
      await depositTx.wait();

      const balancePYYGTokenBefore = BigNumber.from(await PYGGportfolioManagement.balanceOf(await owner.getAddress()));

      // Withdraw WETH from the portfolio
      const withdrawTx = await PYGGportfolioManagement.withdrawInKind(balancePYYGTokenBefore.toBigInt(), {
        amountIn: amountIn,
        directions: [
          {
            path: defaultAbiCoder.encode(["address[]"], [[await TSTToken.getAddress(), await WETH.getAddress()]]),
            version: 0 // Assuming Uniswap V2
          }
        ]
      });
      await withdrawTx.wait();
      
      const balancePYYGShareTokenAfter = BigNumber.from(await PYGGportfolioManagement.balanceOf(await owner.getAddress()));

      expect(balancePYYGTokenBefore.sub(balancePYYGShareTokenAfter)).to.equal(balancePYYGTokenBefore); // Give whole ShareToken back
    });
  });

  describe("Withdraw Fees by Owner", function () {
    it("Should allow the owner to withdraw fees", async function () {
      const amountIn = ethers.parseEther("10");
  
      await (WETH as any).connect(owner).approve(await PYGGportfolioManagement.getAddress(), amountIn);
  
      // Deposit WETH into the portfolio to generate fees
      const depositTx = await PYGGportfolioManagement.deposit({
        directions: [
          {
            path: defaultAbiCoder.encode(["address[]"], [[await WETH.getAddress(), await TSTToken.getAddress()]]),
            version: 0 // Assuming Uniswap V2
          }
        ],
        amountIn: amountIn,
      });
      await depositTx.wait();
  
      // Check the total fees collected
      const totalFeesWETHBefore = await PYGGportfolioManagement.totalFeesWETH();
      expect(totalFeesWETHBefore).to.be.gt(0);
  
      // Withdraw fees by owner
      const receiverFeeAddress = await owner.getAddress();
      const withdrawFeesTx = await PYGGportfolioManagement.withdrawFeesByOwner(receiverFeeAddress);
      await withdrawFeesTx.wait();
  
      // Check the total fees after withdrawal
      const totalFeesWETHAfter = await PYGGportfolioManagement.totalFeesWETH();
      expect(totalFeesWETHAfter).to.equal(0);
  
      // Check the balance of the receiver address
      const receiverBalance = await ethers.provider.getBalance(receiverFeeAddress);
      expect(receiverBalance).to.be.gt(totalFeesWETHBefore);
    });
  });

});