// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PYGGportfolioRebalancer.sol";
import "./interface/IPortfolioFactory.sol";
import { Portfolio } from "./Structs.sol";

contract PortfolioFactory is IPortfolioFactory {

    mapping(address => Portfolio[]) public portfolios;

    uint16 public depositFee;
    uint16 public withdrawalFee;

    address private uniswapV2Router;
    address private uniswapV3Router;
    address private uniswapV3Quoter;

    constructor(address _uniswapV2Router, address _uniswapV3Router, address _uniswapV3Quoter, uint16 _depositFee, uint16 _withdrawalFee) {
        require(_depositFee <= 10000, "!InvalidFee");
        require(_withdrawalFee <= 10000, "!InvalidFee");
        depositFee = _depositFee;
        withdrawalFee = _withdrawalFee;
        uniswapV2Router = _uniswapV2Router;
        uniswapV3Router = _uniswapV3Router;
        uniswapV3Quoter = _uniswapV3Quoter;
    }

    function createPortfolio(string memory _name, string memory _symbol, uint256 _fee, address[] memory _tokens, uint256[] memory _targetPercentages, Version[] memory _versions, uint24[] memory _feeTiers) external {
        require(_tokens.length > 0, "Must include at least one token");
        require(_tokens.length == _targetPercentages.length && _tokens.length == _versions.length && _tokens.length == _feeTiers.length, "!Misslengths");

        // Deploy a new PYGGportfolioRebalancer contract
        PYGGportfolioRebalancer newPortfolio = new PYGGportfolioRebalancer(_name, _symbol, uniswapV2Router, uniswapV3Router, uniswapV3Quoter);
        
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