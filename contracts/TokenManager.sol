// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interface/IUniswapV2Router02.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interface/IUniswapV3Quoter.sol";
import "./interface/IWETH.sol";

contract TokenManager is Ownable, Pausable {
    struct TokenInfo {
        IERC20 token;
        uint256 targetPercentage;
        string version;
        uint24 feeTier;
    }

    TokenInfo[] public portfolio;
    IUniswapV2Router02 public uniswapV2Router;
    ISwapRouter public uniswapV3Router;
    IUniswapV3Quoter public uniswapV3Quoter; // Quoter contract

    uint256 public slippageTolerance; // Slippage tolerance in basis points (e.g., 100 = 1%)

    bytes32 private constant VERSION_V2 = keccak256(abi.encodePacked("v2"));
    bytes32 private constant VERSION_V3 = keccak256(abi.encodePacked("v3"));

    event SlippageToleranceChanged(uint256 newSlippageTolerance);

    constructor(
        address _uniswapV2Router,
        address _uniswapV3Router,
        address _uniswapV3Quoter
    ) Ownable(msg.sender) {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapV3Quoter = IUniswapV3Quoter(_uniswapV3Quoter);
        slippageTolerance = 1000;
    }

    function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
        require(_slippageTolerance <= 10000, "!SLP");
        slippageTolerance = _slippageTolerance;
        emit SlippageToleranceChanged(_slippageTolerance);
    }

    function bulkAddTokens(
        address[] calldata _tokens, 
        uint256[] calldata _targetPercentages, 
        string[] calldata _versions, 
        uint24[] calldata _feeTiers
    )    
    external 
    onlyOwner 
    {
        require(
            _tokens.length == _targetPercentages.length && 
            _tokens.length == _versions.length && 
            _tokens.length == _feeTiers.length, 
            "!Misslengths"
        );
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_targetPercentages[i] <= 10000, "!percentage");

            portfolio.push(TokenInfo({
                token: IERC20(_tokens[i]),
                targetPercentage: _targetPercentages[i],
                version: _versions[i],
                feeTier: _feeTiers[i]
            }));
        }
    }

    function updateToken(
        address _token, 
        uint256 _targetPercentage, 
        string memory _version, 
        uint24 _feeTier
    ) 
    external 
    onlyOwner 
    {
        require(_targetPercentage <= 10000, "!P>10000");

        bool tokenFound = false;

        for (uint256 i = 0; i < portfolio.length; i++) {
         if (address(portfolio[i].token) == _token) {
            portfolio[i].targetPercentage = _targetPercentage;
            portfolio[i].version = _version;
            portfolio[i].feeTier = _feeTier;
            tokenFound = true;
            break;
         }
        }

        require(tokenFound, "!token");
    }

    function getPortfolioValue(uint256[] memory _tokenPrices) public view returns (uint256) {
        require(_tokenPrices.length == portfolio.length, "!priceslength");
        uint256 totalValue = 0;
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenBalance = tokenInfo.token.balanceOf(address(this));
            uint256 tokenPrice = _tokenPrices[i];
            totalValue += tokenBalance * tokenPrice;
        }
        return totalValue;
    }

    function getTargetValuesAtPriceUSD(uint256 _tokenPrice) internal view returns (uint256[] memory) {
        uint256[] memory targetValues = new uint256[](portfolio.length);
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            targetValues[i] = (_tokenPrice * tokenInfo.targetPercentage) / 10000;
        }
        return targetValues;
    }

    function getTokenValueAtPrice(uint256 _price, uint256 tokenBalance) internal pure returns (uint256) {
        return tokenBalance * _price;
    }

    function needsRebalance(uint256[] memory _tokenPrices) external view returns (bool) {
        require(_tokenPrices.length == portfolio.length, "!PL");

        uint256 totalValue = getPortfolioValue(_tokenPrices);
        require(totalValue > 0, "TV>0");

        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 currentPrice = getTokenValueAtPrice(_tokenPrices[i], tokenInfo.token.balanceOf(address(this)));
            require(currentPrice > 0, "CP>0");

            uint256 shareTokenOfPortfolio = (currentPrice * 10000) / totalValue;

            if (shareTokenOfPortfolio > tokenInfo.targetPercentage) {
                return true;
            } else if (shareTokenOfPortfolio < tokenInfo.targetPercentage) {
                return true;
            }
        }

        return false;
    }

    function rebalance(uint256[] memory _tokenPrices) external onlyOwner whenNotPaused {
        require(_tokenPrices.length == portfolio.length, "!PL");

        uint256 totalValue = getPortfolioValue(_tokenPrices);
        require(totalValue > 0, "tv!=0");

        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 currentPrice = getTokenValueAtPrice(_tokenPrices[i], tokenInfo.token.balanceOf(address(this)));
            require(currentPrice > 0, "cp>0");

            uint256 shareTokenOfPortfolio = (currentPrice * 10000) / totalValue;

            if (shareTokenOfPortfolio > tokenInfo.targetPercentage) {
                uint256 excessPercentage = shareTokenOfPortfolio - tokenInfo.targetPercentage;
                uint256 calValuetoUSD = (excessPercentage * totalValue) / 10000;
                uint256 amountOfToken = calValuetoUSD / _tokenPrices[i];
                require(amountOfToken > 0, "amount>0S");
                // Execute sell on Uniswap
                sellTokens(tokenInfo.token, amountOfToken, tokenInfo.version, tokenInfo.feeTier);
            } else if (shareTokenOfPortfolio < tokenInfo.targetPercentage) {
                uint256 excessPercentage = tokenInfo.targetPercentage - shareTokenOfPortfolio;
                uint256 calValuetoUSD = (excessPercentage * totalValue) / 10000;
                uint256 amountOfToken = calValuetoUSD / _tokenPrices[i];
                require(amountOfToken > 0, "amount>0B");
                buyTokens(tokenInfo.token, amountOfToken, tokenInfo.version, tokenInfo.feeTier);
            }
        }
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

            uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
            return swapTokenForETHV3(_token, _amountIn, feeTier, amountOutMinimum, address(this));
        } else {
            revert("!UV");
        }
    }

    function swapETHForToken(IERC20 _token, uint256 _ethAmount, string memory version, uint24 feeTier) external payable {
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

    function swapTokenForETHV2(IERC20 _token, uint256 _amountIn, uint256 amountOutMinimum, address receiver) internal returns (uint256) {
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

    function swapTokenForETHV3(IERC20 _token, uint256 _amountIn, uint24 feeTier, uint256 amountOutMinimum, address receiver) internal returns (uint256) {
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

    function sellTokens(IERC20 _token, uint256 _amount, string memory version, uint24 feeTier) internal returns (uint256 amountOut) {
        require(_amount > 0, ">0");
        require(address(_token) != address(0), "!address");
        require(bytes(version).length > 0, "!empty");
    
        if (keccak256(abi.encodePacked(version)) == VERSION_V2) {
            address[] memory path = new address[](2);
            path[0] = address(_token);
            path[1] = uniswapV2Router.WETH();

            uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_amount, path);
            require(expectedAmounts.length >= 2, "!EXPAM");
            uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;

            amountOut = swapTokenForETHV2(_token, _amount, amountOutMinimum, address(this));
            require(amountOut >= amountOutMinimum, "<amount");
        } else if (keccak256(abi.encodePacked(version)) == VERSION_V3) {
            bytes memory pathV3 = abi.encodePacked(address(_token), feeTier, uniswapV2Router.WETH());
            uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(pathV3, _amount);
            require(expectedAmountOut > 0, "min>0");
            uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;

            amountOut = swapTokenForETHV3(_token, _amount, feeTier, amountOutMinimum, address(this));
            require(amountOut >= amountOutMinimum, "min>0");
        } else {
            revert("!UV");
        }
    }

    function buyTokens(IERC20 _token, uint256 _amountOut, string memory version, uint24 feeTier) internal {
        if (keccak256(abi.encodePacked(version)) == VERSION_V2) {
            address[] memory path = new address[](2);
            path[0] = uniswapV2Router.WETH();
            path[1] = address(_token);
            uint256[] memory expectedAmountsIn = uniswapV2Router.getAmountsIn(_amountOut, path);
            uint256 amountOutMinimum = (expectedAmountsIn[1] * (10000 - slippageTolerance)) / 10000;
            swapETHForTokenV2(_token, expectedAmountsIn[1], amountOutMinimum);
        } else if (keccak256(abi.encodePacked(version)) == VERSION_V3) {
            bytes memory pathV3 = abi.encodePacked(uniswapV2Router.WETH(), feeTier, address(_token));
            uint256 expectedAmountIn = uniswapV3Quoter.quoteExactOutput(pathV3, _amountOut);
            uint256 amountOutMinimum = (expectedAmountIn * (10000 - slippageTolerance)) / 10000;
            swapETHForTokenV3(_token, expectedAmountIn, feeTier, amountOutMinimum);
        } else {
            revert("!UV");
        }
    }
}
