// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import { Version } from "../Structs.sol";

interface IPortfolioFactory {
    struct Portfolio {
        string name;
        string symbol;
        uint256 fee;
        address[] tokens;
        address owner;
        address portfolioAddress;
    }

    event PortfolioCreated(address indexed owner, string name, string symbol, uint256 fee, address[] tokens, address portfolioAddress);

    function depositFee() external view returns (uint16);
    function withdrawalFee() external view returns (uint16);

    function createPortfolio(
        string memory _name,
        string memory _symbol,
        uint256 _fee,
        address[] memory _tokens,
        uint256[] memory _targetPercentages,
        Version[] memory _versions,
        uint24[] memory _feeTiers
    ) external;

    function getPortfolios(address _owner) external view returns (Portfolio[] memory);
}