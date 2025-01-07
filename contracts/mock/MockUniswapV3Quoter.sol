// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockUniswapV3Quoter {
    function quoteExactInput(bytes memory path, uint256 amountIn) external pure returns (uint256 amountOut) {
        amountOut = amountIn * 2;
    }
}