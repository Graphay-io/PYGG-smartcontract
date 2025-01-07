// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PYGGportfolioRebalancer.sol";
import "./WhiteListManager.sol";
import { Portfolio } from "./Structs.sol";

contract PortfolioFactory {

    mapping(address => Portfolio[]) public portfolios;

    IUniswapV2Router02 public uniswapV2Router;
    ISwapRouter public uniswapV3Router;
    IUniswapV3Quoter public uniswapV3Quoter;

    event PortfolioCreated(address indexed owner, string name, string symbol, uint256 fee, address[] tokens, address portfolioAddress);

    constructor(address _uniswapV2Router, address _uniswapV3Router, address _uniswapV3Quoter) {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapV3Quoter = IUniswapV3Quoter(_uniswapV3Quoter);
    }

    function createPortfolio(string memory _name, string memory _symbol, uint256 _fee, address[] memory _tokens, uint256[] memory _targetPercentages, string[] memory _versions, uint24[] memory _feeTiers) external {
        require(_tokens.length > 0, "Must include at least one token");
        require(_tokens.length == _targetPercentages.length && _tokens.length == _versions.length && _tokens.length == _feeTiers.length, "!Misslengths");

        // Deploy a new PYGGportfolioRebalancer contract
        PYGGportfolioRebalancer newPortfolio = new PYGGportfolioRebalancer(_name, _symbol, _fee, _targetPercentages, _versions, _feeTiers);
        
        // Initialize the tokens in the new portfolio
        newPortfolio.initializeTokens(_tokens, _targetPercentages, _versions, _feeTiers);

        // Transfer ownership of the new portfolio to the creator
        newPortfolio.transferOwnership(msg.sender);

        // Store the portfolio details
        portfolios[msg.sender].push(Portfolio({
            name: _name,
            symbol: _symbol,
            fee: _fee,
            tokens: _tokens,
            owner: msg.sender,
            portfolioAddress: address(newPortfolio)
        }));

        emit PortfolioCreated(msg.sender, _name, _symbol, _fee, _tokens, address(newPortfolio));
    }

    function getPortfolios(address _owner) external view returns (Portfolio[] memory) {
        return portfolios[_owner];
    }
}