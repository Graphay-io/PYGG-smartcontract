// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interface/IUniswapV2Router02.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interface/IUniswapV3Quoter.sol";
import "./PYGGportfolioRebalancer.sol";

contract PYGGFactory {

    constructor(PYGGportfolioRebalancer _pyggPortfolioRebalancer, address _uniswapV2Router, address _uniswapV3Router, address _uniswapV3Quoter) {
        _pyggPortfolioRebalancer = new PYGGportfolioRebalancer(_uniswapV2Router, _uniswapV3Router, _uniswapV3Quoter);
    }
}