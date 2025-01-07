// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockUniswapV2Router {
    address public WETH;

    constructor() {
        WETH = address(this);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn * 2;
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn * 2;
        payable(to).transfer(amounts[1]);
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = msg.value * 2;
    }
}