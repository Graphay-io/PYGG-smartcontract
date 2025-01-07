import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { MockUniswapV2Router, MockUniswapV3Router, MockUniswapV3Quoter, PortfolioFactory, PYGGportfolioRebalancer } from "../typechain-types";

describe("PortfolioFactory", function () {
  let portfolioFactory: PortfolioFactory;
  let pyggPortfolioRebalancer: PYGGportfolioRebalancer;
  let mockUniswapV2Router: MockUniswapV2Router;
  let mockUniswapV3Router: MockUniswapV3Router;
  let mockUniswapV3Quoter: MockUniswapV3Quoter;
  let owner: Signer;
  let addr1: Signer;
  let addr2: Signer;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    const MockUniswapV2RouterFactory = await ethers.getContractFactory("MockUniswapV2Router");
    mockUniswapV2Router = (await MockUniswapV2RouterFactory.deploy()) as MockUniswapV2Router;

    const MockUniswapV3RouterFactory = await ethers.getContractFactory("MockUniswapV3Router");
    mockUniswapV3Router = (await MockUniswapV3RouterFactory.deploy()) as unknown as MockUniswapV3Router;

    const MockUniswapV3QuoterFactory = await ethers.getContractFactory("MockUniswapV3Quoter");
    mockUniswapV3Quoter = (await MockUniswapV3QuoterFactory.deploy()) as MockUniswapV3Quoter;

    const PYGGportfolioRebalancerFactory = await ethers.getContractFactory("PYGGportfolioRebalancer");
    pyggPortfolioRebalancer = (await PYGGportfolioRebalancerFactory.deploy(
      await mockUniswapV2Router.getAddress(),
      await mockUniswapV3Router.getAddress(),
      await mockUniswapV3Quoter.getAddress()
    )) as PYGGportfolioRebalancer;

    const PortfolioFactoryFactory = await ethers.getContractFactory("PortfolioFactory");
    portfolioFactory = (await PortfolioFactoryFactory.deploy()) as PortfolioFactory;
  });

  it("should create a new portfolio", async function () {
    const tokens = [await addr1.getAddress(), await addr2.getAddress()];
    const targetPercentages = [5000, 5000];
    const versions = ["v2", "v3"];
    const feeTiers = [3000, 10000];

    await portfolioFactory.createPortfolio(
      "Test Portfolio",
      "TPF",
      100,
      tokens,
      targetPercentages,
      versions,
      feeTiers,
      await mockUniswapV2Router.getAddress(),
      await mockUniswapV3Router.getAddress(),
      await mockUniswapV3Quoter.getAddress()
    );

    const portfolios = await portfolioFactory.getPortfolios(await owner.getAddress());
    expect(portfolios.length).to.equal(1);
    expect(portfolios[0].name).to.equal("Test Portfolio");
    expect(portfolios[0].symbol).to.equal("TPF");
    expect(portfolios[0].fee).to.equal(100);
    expect(portfolios[0].tokens).to.deep.equal(tokens);
  });

  it("should initialize tokens in the new portfolio", async function () {
    const tokens = [await addr1.getAddress(), await addr2.getAddress()];
    const targetPercentages = [5000, 5000];
    const versions = ["v2", "v3"];
    const feeTiers = [3000, 10000];

    await portfolioFactory.createPortfolio(
      "Test Portfolio",
      "TPF",
      100,
      tokens,
      targetPercentages,
      versions,
      feeTiers,
      mockUniswapV2Router.getAddress(),
      mockUniswapV3Router.getAddress(),
      mockUniswapV3Quoter.getAddress()
    );

    const portfolios = await portfolioFactory.getPortfolios(await owner.getAddress());
    const portfolioAddress = portfolios[0].portfolioAddress;
    const portfolio = await ethers.getContractAt("PYGGportfolioRebalancer", portfolioAddress) as PYGGportfolioRebalancer;

    const portfolioTokens = await portfolio.getAllTokens();
    expect(portfolioTokens.length).to.equal(2);
    expect(portfolioTokens[0].token).to.equal(tokens[0]);
    expect(portfolioTokens[1].token).to.equal(tokens[1]);
  });

  it("should allow deposit and withdraw", async function () {
    const tokens = [await addr1.getAddress(), await addr2.getAddress()];
    const targetPercentages = [5000, 5000];
    const versions = ["v2", "v3"];
    const feeTiers = [3000, 10000];

    await portfolioFactory.createPortfolio(
      "Test Portfolio",
      "TPF",
      100,
      tokens,
      targetPercentages,
      versions,
      feeTiers,
      mockUniswapV2Router.getAddress(),
      mockUniswapV3Router.getAddress(),
      mockUniswapV3Quoter.getAddress()
    );

    const portfolios = await portfolioFactory.getPortfolios(await owner.getAddress());
    const portfolioAddress = portfolios[0].portfolioAddress;
    const portfolio = await ethers.getContractAt("PYGGportfolioRebalancer", portfolioAddress) as PYGGportfolioRebalancer;

    await portfolio.deposit({ value: ethers.parseEther("1") });
    expect(await portfolio.balanceOf(await owner.getAddress())).to.equal(ethers.utils.parseEther("0.99"));

    await portfolio.withdraw(ethers.parseEther("0.99"));
    expect(await portfolio.balanceOf(await owner.getAddress())).to.equal(0);
  });

  it("should allow rebalancing by whitelisted users", async function () {
    const tokens = [await addr1.getAddress(), await addr2.getAddress()];
    const targetPercentages = [5000, 5000];
    const versions = ["v2", "v3"];
    const feeTiers = [3000, 10000];

    await portfolioFactory.createPortfolio(
      "Test Portfolio",
      "TPF",
      100,
      tokens,
      targetPercentages,
      versions,
      feeTiers,
      mockUniswapV2Router.getAddress(),
      mockUniswapV3Router.getAddress(),
      mockUniswapV3Quoter.getAddress()
    );

    const portfolios = await portfolioFactory.getPortfolios(await owner.getAddress());
    const portfolioAddress = portfolios[0].portfolioAddress;
    const portfolio = await ethers.getContractAt("PYGGportfolioRebalancer", portfolioAddress) as PYGGportfolioRebalancer;

    await portfolio.setWhitelist(await addr1.getAddress(), true);
    // await portfolio.connect(addr1).rebalance();
  });

  it("should allow pausing and unpausing by the owner", async function () {
    const tokens = [await addr1.getAddress(), await addr2.getAddress()];
    const targetPercentages = [5000, 5000];
    const versions = ["v2", "v3"];
    const feeTiers = [3000, 10000];

    await portfolioFactory.createPortfolio(
      "Test Portfolio",
      "TPF",
      100,
      tokens,
      targetPercentages,
      versions,
      feeTiers,
      mockUniswapV2Router.getAddress(),
      mockUniswapV3Router.getAddress(),
      mockUniswapV3Quoter.getAddress()
    );

    const portfolios = await portfolioFactory.getPortfolios(await owner.getAddress());
    const portfolioAddress = portfolios[0].portfolioAddress;
    const portfolio = await ethers.getContractAt("PYGGportfolioRebalancer", portfolioAddress) as PYGGportfolioRebalancer;

    await portfolio.pause();
    await expect(portfolio.deposit({ value: ethers.parseEther("1") })).to.be.revertedWith("Pausable: paused");

    await portfolio.unpause();
    await portfolio.deposit({ value: ethers.parseEther("1") });
  });

  it("should allow setting deposit and withdrawal fees by the owner", async function () {
    const tokens = [await addr1.getAddress(), await addr2.getAddress()];
    const targetPercentages = [5000, 5000];
    const versions = ["v2", "v3"];
    const feeTiers = [3000, 10000];

    await portfolioFactory.createPortfolio(
      "Test Portfolio",
      "TPF",
      100,
      tokens,
      targetPercentages,
      versions,
      feeTiers,
      mockUniswapV2Router.getAddress(),
      mockUniswapV3Router.getAddress(),
      mockUniswapV3Quoter.getAddress()
    );

    const portfolios = await portfolioFactory.getPortfolios(await owner.getAddress());
    const portfolioAddress = portfolios[0].portfolioAddress;
    const portfolio = await ethers.getContractAt("PYGGportfolioRebalancer", portfolioAddress) as PYGGportfolioRebalancer;

    const withdrawFee = 200;
    const depositFee = 200;

    await portfolio.setFees(depositFee, withdrawFee);

    await portfolio.deposit({ value: ethers.parseEther("1") });
    expect(await portfolio.balanceOf(await owner.getAddress())).to.equal(ethers.utils.parseEther("0.98"));

    await portfolio.withdraw(ethers.parseEther("0.98"));
    expect(await portfolio.balanceOf(await owner.getAddress())).to.equal(0);
  });
});