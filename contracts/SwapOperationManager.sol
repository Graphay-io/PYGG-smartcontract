// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/IUniswapV2Router02.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interface/IUniswapV3Quoter.sol";
import { FailedSwap } from "./Structs.sol";
import "./interface/IWETH.sol";

abstract contract SwapOperationManager {
    IUniswapV2Router02 public uniswapV2Router;
    ISwapRouter public uniswapV3Router;
    IUniswapV3Quoter public uniswapV3Quoter;
    FailedSwap[] public failedSwaps;

    uint256 public slippageTolerance;
    uint256 public profitToETH;
    uint256 public profitToWETH;
    

    mapping(address => uint256) public userFailedSwaps;

    bytes32 private constant VERSION_V2 = keccak256(abi.encodePacked("v2"));
    bytes32 private constant VERSION_V3 = keccak256(abi.encodePacked("v3"));

    constructor(address _uniswapV2Router, address _uniswapV3Router, address _uniswapV3Quoter) {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapV3Quoter = IUniswapV3Quoter(_uniswapV3Quoter);
        slippageTolerance = 1000;
    }

    function retryFailedSwaps(address user) external {
        for (uint256 i = 0; i < failedSwaps.length; i++) {
            if (failedSwaps[i].user == user) {
                FailedSwap memory failedSwap = failedSwaps[i];
                if(keccak256(abi.encodePacked(failedSwap.version)) == VERSION_V3){
                    IWETH(uniswapV2Router.WETH()).deposit{value: failedSwap.amount}();
                    try this.swapETHForToken(failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier) {
                        removeFailedSwap(i);
                        userFailedSwaps[user]--;
                    } catch {
                        failedSwaps.push(FailedSwap(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier));
                        userFailedSwaps[msg.sender]++;
                        // emit SwapFailed(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version);
                    }
                } else if (keccak256(abi.encodePacked(failedSwap.version)) == VERSION_V2) {
                    try this.swapETHForToken{value: failedSwap.amount}(failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier) {
                        removeFailedSwap(i);
                        userFailedSwaps[user]--;
                    } catch {
                        failedSwaps.push(FailedSwap(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier));
                        userFailedSwaps[msg.sender]++;
                        // emit SwapFailed(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version);
                    }
                }
            }
        }
    }

    function getFailedSwaps(address user) external view returns (FailedSwap[] memory) {
        FailedSwap[] memory userFailedSwapsArray = new FailedSwap[](userFailedSwaps[user]);
        uint256 counter = 0;
        for (uint256 i = 0; i < failedSwaps.length; i++) {
            if (failedSwaps[i].user == user) {
                userFailedSwapsArray[counter] = failedSwaps[i];
                counter++;
            }
        }
        return userFailedSwapsArray;
    }

    function removeFailedSwap(uint256 index) internal {
        require(index < failedSwaps.length, "!index");
        failedSwaps[index] = failedSwaps[failedSwaps.length - 1];
        failedSwaps.pop();
    }

    function swapTokenForETH(IERC20 _token, uint256 _amountIn, string memory version, uint24 feeTier) external returns (uint256) {
        if (keccak256(abi.encodePacked(version)) == VERSION_V2) {
            address[] memory path = new address[](2);
            path[0] = address(_token);
            path[1] = uniswapV2Router.WETH();
            uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_amountIn, path);
            uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;
            return swapTokenForETHV2(_token, _amountIn, amountOutMinimum, address(this));
        } else if (keccak256(abi.encodePacked(version)) == VERSION_V3) {
            bytes memory path = abi.encodePacked(address(_token), feeTier, uniswapV2Router.WETH());
            uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(path, _amountIn);

            // Calculate the minimum amount of ETH to receive, considering slippage tolerance
            uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
            return swapTokenForETHV3(_token, _amountIn, feeTier, amountOutMinimum, address(this));
        } else {
            revert("!UV");
        }
    }

    function swapETHForToken(IERC20 _token, uint256 _ethAmount, string memory version, uint24 feeTier) public payable {
        // Calculate the minimum amount of tokens to receive, considering slippage tolerance
        if (keccak256(abi.encodePacked(version)) == VERSION_V2) {
            address[] memory path = new address[](2);
            path[0] = uniswapV2Router.WETH();
            path[1] = address(_token);
            uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_ethAmount, path);
            uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;
            swapETHForTokenV2(_token, _ethAmount, amountOutMinimum);
        } else if (keccak256(abi.encodePacked(version)) == VERSION_V3) {
            bytes memory path = abi.encodePacked(uniswapV2Router.WETH(), feeTier, address(_token));
            uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(path, _ethAmount);
            uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
            swapETHForTokenV3(_token, _ethAmount, feeTier, amountOutMinimum);
        } else {
            revert("!UV");
        }
    }

    function swapTokenForETHV2(IERC20 _token, uint256 _amountIn, uint256 amountOutMinimum, address receiver) public returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(_token);
        path[1] = uniswapV2Router.WETH();
        _token.approve(address(uniswapV2Router), _amountIn);
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForETH(
            _amountIn,
            amountOutMinimum, // minimum amount of ETH to receive
            path,
            receiver,
            block.timestamp
        );

        return amounts[1];
    }

    function swapETHForTokenV2(IERC20 _token, uint256 _ethAmount, uint256 amountOutMinimum) internal returns (uint256[] memory amounts) {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(_token);

        amounts = uniswapV2Router.swapExactETHForTokens{value: _ethAmount}(
            amountOutMinimum, // minimum amount of tokens to receive
            path,
            address(this),
            block.timestamp
        );

        return amounts;
    }

    function swapTokenForETHV3(IERC20 _token, uint256 _amountIn, uint24 feeTier, uint256 amountOutMinimum, address receiver) public returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(_token),
            tokenOut: uniswapV2Router.WETH(),
            fee: feeTier, // Pool fee tier
            recipient: receiver,
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: amountOutMinimum, // minimum amount of ETH to receive
            sqrtPriceLimitX96: 0
        });

        _token.approve(address(uniswapV3Router), _amountIn);
        return uniswapV3Router.exactInputSingle(params);
    }

    function swapETHForTokenV3(IERC20 _token, uint256 _ethAmount, uint24 feeTier, uint256 amountOutMinimum) internal {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: uniswapV2Router.WETH(),
            tokenOut: address(_token),
            fee: feeTier, // Pool fee tier
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _ethAmount,
            amountOutMinimum: amountOutMinimum, // minimum amount of tokens to receive
            sqrtPriceLimitX96: 0
        });

        
        uniswapV3Router.exactInputSingle{value: _ethAmount}(params);
    }

    function sellTokens(IERC20 _token, uint256 _amount, string memory version, uint24 feeTier) internal returns(uint256 amountOut){
        if (keccak256(abi.encodePacked(version)) == VERSION_V2) {
            address[] memory path = new address[](2);
            path[0] = address(_token);
            path[1] = uniswapV2Router.WETH();

            uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_amount, path);
            uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;

            amountOut = swapTokenForETHV2(_token, _amount, amountOutMinimum, address(this));
            profitToETH += amountOut;
        } else if (keccak256(abi.encodePacked(version)) == VERSION_V3) {
            bytes memory pathV3 = abi.encodePacked(address(_token), feeTier, uniswapV2Router.WETH());
            uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(pathV3, _amount);
            uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;

            amountOut = swapTokenForETHV3(_token, _amount, feeTier, amountOutMinimum, address(this));
            profitToWETH += amountOut;
        } else {
            revert("Invalid Uniswap version");
        }
    }

    function buyTokens(IERC20 _token, uint256 _amountOut, string memory version, uint24 feeTier) internal {
       if (keccak256(abi.encodePacked(version)) == VERSION_V2) {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(_token);
        uint256[] memory expectedAmountsIn = uniswapV2Router.getAmountsIn(_amountOut, path);
        
        uint256 ethToUse = (profitToETH > expectedAmountsIn[0]) ? expectedAmountsIn[0] : profitToETH;
        require(ethToUse > 0, "eth to use is zero");

        uint256[] memory expectedAmountsOut = uniswapV2Router.getAmountsOut(ethToUse, path);
        uint256 amountOutMinimum = (expectedAmountsOut[1] * (10000 - slippageTolerance)) / 10000;
        
        swapETHForTokenV2(_token, ethToUse, amountOutMinimum);
       } else if (keccak256(abi.encodePacked(version)) == VERSION_V3) {
        bytes memory pathV3 = abi.encodePacked(uniswapV2Router.WETH(), feeTier, address(_token));
        uint256 expectedAmountIn = uniswapV3Quoter.quoteExactOutput(pathV3, _amountOut);
        
        uint256 ethToUse = (profitToWETH > expectedAmountIn) ? expectedAmountIn : profitToWETH;
        require(ethToUse > 0, "eth to use is zero");
        uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(pathV3, ethToUse);
        uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;

        swapETHForTokenV3(_token, ethToUse, feeTier, amountOutMinimum);
      } else {
        revert("Invalid Uniswap version");
      }
    }

    
    function setSlippageTolerance(uint256 _slippageTolerance) external {
        require(_slippageTolerance <= 10000, "!SLP");
        slippageTolerance = _slippageTolerance;
        // emit SlippageToleranceChanged(_slippageTolerance);
    }

    function getWETHaddress() public view returns(address) {
        return uniswapV2Router.WETH();
    }
}
