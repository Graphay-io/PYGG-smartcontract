// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/IUniswapV2Router02.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interface/IUniswapV3Quoter.sol";
import { FailedSwap, Version, SwapPath } from "./Structs.sol";
import "./interface/IWETH.sol";

abstract contract SwapOperationManager {

    FailedSwap[] public failedSwaps;

    uint256 public slippageTolerance;
    
    mapping(address => uint256) public userFailedSwaps;

    IUniswapV2Router02 public uniswapV2Router;
    ISwapRouter public uniswapV3Router;
    IUniswapV3Quoter public uniswapV3Quoter;

    constructor(address _uniswapV2Router, address _uniswapV3Router, address _uniswapV3Quoter) {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapV3Quoter = IUniswapV3Quoter(_uniswapV3Quoter);
        slippageTolerance = 1000;
    }

    // function retryFailedSwaps(address user) external {
    //     for (uint256 i = 0; i < failedSwaps.length; i++) {
    //         if (failedSwaps[i].user == user) {
    //             FailedSwap memory failedSwap = failedSwaps[i];
    //             if(failedSwap.version == Version.V3){
    //                 IWETH(uniswapV2Router.WETH()).deposit{value: failedSwap.amount}();
    //                 try this.swapETHForToken(failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier) {
    //                     removeFailedSwap(i);
    //                     userFailedSwaps[user]--;
    //                 } catch {
    //                     failedSwaps.push(FailedSwap(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier));
    //                     userFailedSwaps[msg.sender]++;
    //                     // emit SwapFailed(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version);
    //                 }
    //             } else if (failedSwap.version == Version.V2) {
    //                 try this.swapETHForToken{value: failedSwap.amount}(failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier) {
    //                     removeFailedSwap(i);
    //                     userFailedSwaps[user]--;
    //                 } catch {
    //                     failedSwaps.push(FailedSwap(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier));
    //                     userFailedSwaps[msg.sender]++;
    //                     // emit SwapFailed(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version);
    //                 }
    //             }
    //         }
    //     }
    // }

    // function getFailedSwaps(address user) external view returns (FailedSwap[] memory) {
    //     FailedSwap[] memory userFailedSwapsArray = new FailedSwap[](userFailedSwaps[user]);
    //     uint256 counter = 0;
    //     for (uint256 i = 0; i < failedSwaps.length; i++) {
    //         if (failedSwaps[i].user == user) {
    //             userFailedSwapsArray[counter] = failedSwaps[i];
    //             counter++;
    //         }
    //     }
    //     return userFailedSwapsArray;
    // }

    // function removeFailedSwap(uint256 index) internal {
    //     require(index < failedSwaps.length, "!index");
    //     failedSwaps[index] = failedSwaps[failedSwaps.length - 1];
    //     failedSwaps.pop();
    // }

    function swapTokenForToken(IERC20 _token, uint256 _amountIn, Version _version, address _receiver, bytes memory _path) external returns (uint256) {
        if (_version == Version.V2) {
            return swapTokenForTokenV2(_token, _amountIn, _receiver, _path);
        } else if (_version == Version.V3) {
            return swapTokenForTokenV3(_token, _amountIn, _receiver, _path);
        } else {
            revert("!UV");
        }
    }

    // function swapETHForToken(IERC20 _token, uint256 _ethAmount, Version version, uint24 feeTier, bytes path) external payable {
    //     // Calculate the minimum amount of tokens to receive, considering slippage tolerance
    //     if (version == Version.V2) {
    //         swapETHForTokenV2(_token, _ethAmount);
    //     } else if (version == Version.V3) {
    //         swapETHForTokenV3(_token, _ethAmount, feeTier);
    //     } else {
    //         revert("!UV");
    //     }
    // }

    function swapTokenForTokenV2(IERC20 _token, uint256 _amountIn, address receiver, bytes memory path) internal returns (uint256) {
        address[] memory pathArray = abi.decode(path, (address[]));
        uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_amountIn, pathArray);
        uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;

        _token.approve(address(uniswapV2Router), _amountIn);
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForETH(
            _amountIn,
            amountOutMinimum, // minimum amount of ETH to receive
            pathArray,
            receiver,
            block.timestamp
        );

        return amounts[1];
    }

    // function swapETHForTokenV2(IERC20 _token, uint256 _ethAmount, bytes memory path) internal returns (uint256[] memory amounts) {
    //     uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_ethAmount, path);
    //     uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;
    //     amounts = uniswapV2Router.swapExactETHForTokens{value: _ethAmount}(
    //         amountOutMinimum, // minimum amount of tokens to receive
    //         path,
    //         address(this),
    //         block.timestamp
    //     );

    //     return amounts;
    // }

    function swapTokenForTokenV3(IERC20 _token, uint256 _amountIn, address receiver, bytes memory path) internal returns (uint256) {
        uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(path, _amountIn);
        // Calculate the minimum amount of ETH to receive, considering slippage tolerance
        uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: receiver,
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