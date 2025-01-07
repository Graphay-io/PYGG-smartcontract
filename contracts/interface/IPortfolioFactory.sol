// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import { Version, Portfolio } from "../Structs.sol";

interface IPortfolioFactory {

    event PortfolioCreated(address indexed owner, string name, string symbol, address[] tokens, address portfolioAddress);

    function createPortfolio(
        string memory _name,
        string memory _symbol,
        uint16 _withdrawalFee,
        uint16 _depositFee,
        address[] memory _tokens,
        uint256[] memory _targetPercentages
    ) external;

    function getPortfolios(address _owner) external view returns (Portfolio[] memory);
}