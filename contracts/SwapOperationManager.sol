// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/IUniswapV2Router02.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interface/IUniswapV3Quoter.sol";
import { Version, SwapPath } from "./Structs.sol";
import "./interface/IWETH.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

abstract contract SwapOperationManager {

    uint256 public slippageTolerance;
    address internal vaultContract;

    IUniswapV2Router02 public uniswapV2Router;
    ISwapRouter public uniswapV3Router;
    IUniswapV3Quoter public uniswapV3Quoter;

    constructor(address _uniswapV2Router, address _uniswapV3Router, address _uniswapV3Quoter) {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapV3Quoter = IUniswapV3Quoter(_uniswapV3Quoter);
        slippageTolerance = 1000;
    }

    modifier onlyVaultContract() {
        require(msg.sender == vaultContract, "Not allowed");
        _;
    }

    function setVaultContract(address _vaultContract) internal {
        vaultContract = _vaultContract;
    }

    function swapTokenForToken(IERC20 _token, uint256 _amountIn, Version _version, address _receiver, bytes memory _path) external onlyVaultContract returns (uint256) {
        if (_version == Version.V2) {
            return swapTokenForTokenV2(_token, _amountIn, _receiver, _path);
        } else if (_version == Version.V3) {
            return swapTokenForTokenV3(_token, _amountIn, _receiver, _path);
        } else {
            revert("!UV");
        }
    }

    function swapTokenForTokenV2(
        IERC20 _token, 
        uint256 _amountIn, 
        address receiver, 
        bytes memory path
    ) internal returns (uint256) {
        // Decode the path (sequence of tokens in the swap)
        address[] memory pathArray = abi.decode(path, (address[]));
    
        // Get the expected output amounts using Uniswap V2 Router's getAmountsOut
        uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_amountIn, pathArray);
    
        // Calculate the minimum amount of the output token (with slippage tolerance)
        uint256 amountOutMinimum = (expectedAmounts[expectedAmounts.length - 1] * (10000 - slippageTolerance)) / 10000;

        // Approve the router to spend the input token
        _token.approve(address(uniswapV2Router), _amountIn);

         // Perform the token-to-token swap
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(
            _amountIn,
            amountOutMinimum, // minimum amount of output token to receive
            pathArray,
            receiver,
            block.timestamp
        );

        // Return the actual amount of output token received
        return amounts[amounts.length - 1];
    }   


    function swapTokenForTokenV3(IERC20 _token, uint256 _amountIn, address _receiver, bytes memory _path) internal returns (uint256) {
        
        uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(_path, _amountIn);

        // Calculate the minimum amount of ETH to receive, considering slippage tolerance
        uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: _path,
            recipient: _receiver,
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: amountOutMinimum
        });

        _token.approve(address(uniswapV3Router), _amountIn);
        return uniswapV3Router.exactInput(params);
    }

    function swapETHForTokenV3(uint256 _ethAmount, bytes memory path) internal {
        uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(path, _ethAmount);
        uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: _ethAmount,
            amountOutMinimum: amountOutMinimum
        });

        uniswapV3Router.exactInput{value: _ethAmount}(params);
    }
    
    function setSlippageTolerance(uint256 _slippageTolerance) external {
        require(_slippageTolerance <= 10000, "!SLP");
        slippageTolerance = _slippageTolerance;
    }
}