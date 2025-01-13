// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockUniswapV2Router {
    address public WETH;

    constructor() {
        WETH = address(this);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            amounts[i] = amountIn * (i + 1);
        }
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            amounts[i] = amountIn * (i + 1);
        }
        payable(to).transfer(amounts[amounts.length - 1]);
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            amounts[i] = msg.value * (i + 1);
        }
    }
}