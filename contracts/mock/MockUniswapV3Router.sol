pragma solidity ^0.8.0;

contract MockUniswapV3Router {
    function exactInputSingle(bytes memory params) external payable returns (uint256 amountOut) {
        amountOut = msg.value * 2;
    }
}