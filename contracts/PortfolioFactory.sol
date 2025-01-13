// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./PYGGportfolioManagement.sol";
import "./interface/IPortfolioFactory.sol";
import { Portfolio, Basket } from "./Structs.sol";

contract PortfolioFactory is IPortfolioFactory {

    mapping(address => Portfolio[]) public portfolios;

    address public uniswapV2Router;
    address public uniswapV3Router;
    address public uniswapV3Quoter;

    constructor(address _uniswapV2Router, address _uniswapV3Router, address _uniswapV3Quoter) {
        uniswapV2Router = _uniswapV2Router;
        uniswapV3Router = _uniswapV3Router;
        uniswapV3Quoter = _uniswapV3Quoter;
    }

    function createPortfolio(
        string memory _name,
        string memory _symbol,
        uint16 _withdrawalFee,
        uint16 _depositFee,
        address[] memory _tokens,
        uint256[] memory _targetPercentages
    ) external override {
        require(_tokens.length > 0, "Must include at least one token");
        require(_tokens.length == _targetPercentages.length, "!Misslengths");

        // Deploy a new PYGGportfolioManagement contract
        PYGGportfolioManagement newPortfolio = new PYGGportfolioManagement(_name, _symbol, uniswapV2Router, uniswapV3Router, uniswapV3Quoter);
        
        // Initialize the tokens in the new portfolio
        newPortfolio.initializeTokens(_tokens, _targetPercentages, _withdrawalFee, _depositFee);

        // Transfer ownership of the new portfolio to the creator
        newPortfolio.transferOwnership(msg.sender);

        // Store the portfolio details
        portfolios[msg.sender].push(Portfolio({
            name: _name,
            symbol: _symbol,
            tokens: _tokens,
            owner: msg.sender,
            portfolioAddress: address(newPortfolio)
        }));

        emit PortfolioCreated(msg.sender, _name, _symbol, _tokens, _targetPercentages, address(newPortfolio));
    }

    function getPortfolios(address _owner) external view override returns (Portfolio[] memory) {
        return portfolios[_owner];
    }
}