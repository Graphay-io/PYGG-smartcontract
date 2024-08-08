// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interface/IUniswapV2Router02.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interface/IUniswapV3Quoter.sol";

contract PYGGportfolioRebalancerGpt is Ownable, Pausable, ERC20 {

    struct TokenInfo {
        IERC20 token;
        uint256 targetPercentage; // Target allocation in basis points (e.g., 40% -> 4000)'
        string version;           // Uniswap version (e.g., "v2" or "v3")
        uint24 feeTier;           // Uniswap v3 fee tier (ignored for v2)
    }

    struct FailedSwap {
        address user;
        IERC20 token;
        uint256 amount;
        string version;
        uint24 feeTier;
    }

    TokenInfo[] public portfolio;
    IUniswapV2Router02 public uniswapV2Router;
    ISwapRouter public uniswapV3Router;
    IUniswapV3Quoter public uniswapV3Quoter; // Quoter contract
    mapping(address => bool) public whitelist;
    FailedSwap[] public failedSwaps;
    mapping(address => uint256) public userFailedSwaps;
    mapping(address => uint256) public ethDepositedFailed;

    uint256 public depositFee; // Fee in basis points (e.g., 100 = 1%)
    uint256 public withdrawalFee; // Fee in basis points (e.g., 100 = 1%)
    uint256 public slippageTolerance; // Slippage tolerance in basis points (e.g., 100 = 1%)
    uint256 public totalFees;
    uint256 public profitToETH;

    event Deposited(address indexed user, uint256 amount, uint256 shares, string version);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event Rebalanced(uint256 timestamp);
    event Whitelisted(address indexed user, bool isWhitelisted);
    event SwapFailed(address indexed user, IERC20 token, uint256 amount, string version);
    event SlippageToleranceChanged(uint256 newSlippageTolerance);

    constructor(address _uniswapV2Router, address _uniswapV3Router, address _uniswapV3Quoter)
        Ownable(msg.sender) ERC20("PYGG Wrapped Portfolio", "PYGG")
    {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapV3Quoter = IUniswapV3Quoter(_uniswapV3Quoter);
        whitelist[msg.sender] = true;
        slippageTolerance = 1000;
        withdrawalFee = 100;
        depositFee = 100;
    }

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "Not whitelisted");
        _;
    }

    function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
        require(_slippageTolerance <= 10000, "Invalid slippage tolerance");
        slippageTolerance = _slippageTolerance;
        emit SlippageToleranceChanged(_slippageTolerance);
    }

    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }

    function withdrawAllToETH() external onlyOwner {
        uint256 totalETH = 0;
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenBalance = tokenInfo.token.balanceOf(address(this));
            if (keccak256(abi.encodePacked(tokenInfo.version)) == keccak256(abi.encodePacked("v2"))) {
                address[] memory path = new address[](2);
                path[0] = address(tokenInfo.token);
                path[1] = uniswapV2Router.WETH();
                uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(tokenBalance, path);
                uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;
                totalETH += swapTokenForETHV2(tokenInfo.token, tokenBalance, amountOutMinimum, msg.sender);
            } else if (keccak256(abi.encodePacked(tokenInfo.version)) == keccak256(abi.encodePacked("v3"))) {
                bytes memory path = abi.encodePacked(address(tokenInfo.token), tokenInfo.feeTier, uniswapV2Router.WETH());
                uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(path, tokenBalance);
                uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
                totalETH += swapTokenForETHV3(tokenInfo.token, tokenBalance, tokenInfo.feeTier, amountOutMinimum, msg.sender);
            } else {
                revert("Invalid Uniswap version");
            }
        }

        (bool success, ) = msg.sender.call{value: totalETH}("");
        require(success, "ETH transfer failed");
    }

    function setWhitelist(address _user, bool _status) external onlyOwner {
        whitelist[_user] = _status;
        emit Whitelisted(_user, _status);
    }

    function setFees(uint256 _depositFee, uint256 _withdrawalFee) external onlyOwner {
        require(_depositFee <= 10000, "Invalid deposit fee");
        require(_withdrawalFee <= 10000, "Invalid withdrawal fee");
        depositFee = _depositFee;
        withdrawalFee = _withdrawalFee;
    }

    function withdrawFeesByOwner(address _receiverFeeAddress) external onlyOwner {
        (bool success, ) = _receiverFeeAddress.call{value: totalFees}("");
        require(success, "ETH transfer failed");
    }

    function addToken(address _token, uint256 _targetPercentage, string memory _version, uint24 _feeTier) external onlyOwner {
        require(_targetPercentage <= 10000, "Invalid percentage");
        portfolio.push(TokenInfo({
            token: IERC20(_token),
            targetPercentage: _targetPercentage,
            version: _version,
            feeTier: _feeTier
        }));
    }

    function deposit() external payable onlyWhitelisted whenNotPaused {
        require(msg.value > 0, "Amount must be greater than zero");

        uint256 fee = (msg.value * depositFee) / 10000;
        uint256 amountAfterFee = msg.value - fee;
        totalFees += fee;

        require(amountAfterFee > 0, "Amount after fee must be greater than zero");
        _mint(msg.sender, amountAfterFee);
        emit Deposited(msg.sender, amountAfterFee, amountAfterFee, "N/A");

        // Swap ETH to portfolio tokens
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 calEthAmount = (amountAfterFee * tokenInfo.targetPercentage) / 10000;
            require(calEthAmount <= amountAfterFee, "Calculated ETH amount exceeds available amount");
            this.swapETHForToken{value: calEthAmount}(tokenInfo.token, calEthAmount, tokenInfo.version, tokenInfo.feeTier);
            // try this.swapETHForToken{value: calEthAmount}(tokenInfo.token, calEthAmount, tokenInfo.version, tokenInfo.feeTier) {} catch {
            //     ethDepositedFailed[msg.sender] += calEthAmount;
            //     failedSwaps.push(FailedSwap(msg.sender, tokenInfo.token, calEthAmount, tokenInfo.version, tokenInfo.feeTier));
            //     userFailedSwaps[msg.sender]++;
            //     emit SwapFailed(msg.sender, tokenInfo.token, calEthAmount, tokenInfo.version);
            // }
            // Adjust amountAfterFee to reflect the used ETH
            amountAfterFee -= calEthAmount;
        }
    }

    function withdrawToETH(uint256 tokenAmount) external whenNotPaused {
        require(tokenAmount > 0, "Amount must be greater than zero");
        require(this.balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

        uint256 percentage = (tokenAmount * 10000) / totalSupply();

        require(percentage > 0 && percentage <= 10000, "Percentage must be between 0 and 10000");

        uint256 sharesToWithdraw = (totalSupply() * percentage) / 10000;

        require(sharesToWithdraw > 0, "Amount must be greater than zero");

        _burn(msg.sender, tokenAmount);

        uint256 totalETH = 0;
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenAmountToWithdraw = (tokenInfo.token.balanceOf(address(this)) * sharesToWithdraw) / totalSupply();
            uint256 fee = (tokenAmountToWithdraw * withdrawalFee) / 10000; 
            uint256 amountAfterFee = tokenAmountToWithdraw - fee;
            // uint256 ethReceived = this.swapTokenForETH(tokenInfo.token, amountAfterFee, tokenInfo.version, tokenInfo.feeTier);
            // totalETH += ethReceived;
        }

        uint256 feeETH = (totalETH * withdrawalFee) / 10000;
        uint256 amountAfterFee = totalETH - feeETH;
        totalFees += feeETH;
        uint256 failedETHsUser = ethDepositedFailed[msg.sender];
        uint256 totalTransferAmount = failedETHsUser + amountAfterFee;
        (bool success, ) = msg.sender.call{value: totalTransferAmount}("");
        require(success, "ETH transfer failed");

        emit Withdrawn(msg.sender, totalETH, sharesToWithdraw);
    }

    function withdraw(uint256 tokenAmount) external whenNotPaused {
        require(tokenAmount > 0, "Amount must be greater than zero");
        require(this.balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

        uint256 userShare = (tokenAmount * 10000) / totalSupply();

        require(userShare > 0 && userShare <= 10000, "Percentage must be between 0 and 10000");

        uint256 sharesToWithdraw = (totalSupply() * userShare) / 10000;

        require(sharesToWithdraw > 0, "Amount must be greater than zero");

        _burn(msg.sender, tokenAmount);

        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenAmountToWithdraw = (tokenInfo.token.balanceOf(address(this)) * sharesToWithdraw) / totalSupply();
            uint256 fee = (tokenAmountToWithdraw * withdrawalFee) / 10000;
            uint256 amountAfterFee = tokenAmountToWithdraw - fee;
            tokenInfo.token.transfer(msg.sender, amountAfterFee);
            if (keccak256(abi.encodePacked(tokenInfo.version)) == keccak256(abi.encodePacked("v2"))) {
                address[] memory path = new address[](2);
                path[0] = address(tokenInfo.token);
                path[1] = uniswapV2Router.WETH();
                uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(fee, path);
                uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;
                totalFees += swapTokenForETHV2(tokenInfo.token, fee, amountOutMinimum, address(this));
            } else if (keccak256(abi.encodePacked(tokenInfo.version)) == keccak256(abi.encodePacked("v3"))) {
                bytes memory path = abi.encodePacked(address(tokenInfo.token), tokenInfo.feeTier, uniswapV2Router.WETH());
                uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(path, fee);
                uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
                totalFees += swapTokenForETHV3(tokenInfo.token, fee, tokenInfo.feeTier, amountOutMinimum, address(this));
            } else {
                revert("Invalid Uniswap version");
            }
        }
        uint256 failedETHsUser = (ethDepositedFailed[msg.sender] * userShare) / 10000;
        uint256 totalTransferAmount = failedETHsUser;
        (bool success, ) = msg.sender.call{value: totalTransferAmount}("");
        require(success, "transfer will revert");
        emit Withdrawn(msg.sender, userShare, sharesToWithdraw);
    }

    function retryFailedSwaps(address user) external onlyOwner {
        for (uint256 i = 0; i < failedSwaps.length; i++) {
            if (failedSwaps[i].user == user) {
                FailedSwap memory failedSwap = failedSwaps[i];
                try this.swapETHForToken{value: failedSwap.amount}(failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier) {
                    removeFailedSwap(i);
                    userFailedSwaps[user]--;
                } catch {
                    failedSwaps.push(FailedSwap(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version, failedSwap.feeTier));
                    userFailedSwaps[msg.sender]++;
                    emit SwapFailed(msg.sender, failedSwap.token, failedSwap.amount, failedSwap.version);
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
        require(index < failedSwaps.length, "Invalid index");
        failedSwaps[index] = failedSwaps[failedSwaps.length - 1];
        failedSwaps.pop();
    }

    function getPortfolioValue(uint256[] memory _tokenPrices) public view returns (uint256) {
        require(_tokenPrices.length == portfolio.length, "Invalid prices length");
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

    function rebalance(uint256[] memory _tokenPrices) external onlyOwner whenNotPaused {
        require(_tokenPrices.length == portfolio.length, "Invalid prices length");

        uint256 totalValue = getPortfolioValue(_tokenPrices);

        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 currentPrice = getTokenValueAtPrice(_tokenPrices[i], tokenInfo.token.balanceOf(address(this)));
            uint256 shareTokenOfPortfolio = (currentPrice * 10000) / totalValue;

            if (shareTokenOfPortfolio > tokenInfo.targetPercentage) {
                uint256 excessPercentage = shareTokenOfPortfolio - tokenInfo.targetPercentage;
                uint256 calValuetoUSD = (excessPercentage * totalValue) / 10000;
                uint256 amountOfToken = calValuetoUSD / currentPrice;
                // Execute sell on Uniswap
                sellTokens(tokenInfo.token, amountOfToken, tokenInfo.version, tokenInfo.feeTier);
            } else if (shareTokenOfPortfolio < tokenInfo.targetPercentage) {
                uint256 excessPercentage = tokenInfo.targetPercentage - shareTokenOfPortfolio;
                uint256 calValuetoUSD = (excessPercentage * totalValue) / 10000;
                uint256 amountOfToken = calValuetoUSD / currentPrice;
                // Execute buy on Uniswap
                buyTokens(tokenInfo.token, amountOfToken, tokenInfo.version, tokenInfo.feeTier);
            }
        }

        emit Rebalanced(block.timestamp);
    }

    function swapTokenForETH(IERC20 _token, uint256 _amountIn, string memory version, uint24 feeTier) external returns (uint256) {
        if (keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("v2"))) {
            address[] memory path = new address[](2);
            path[0] = address(_token);
            path[1] = uniswapV2Router.WETH();
            uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_amountIn, path);
            uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;
            return swapTokenForETHV2(_token, _amountIn, amountOutMinimum, address(this));
        } else if (keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("v3"))) {
            bytes memory path = abi.encodePacked(address(_token), feeTier, uniswapV2Router.WETH());
            uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(path, _amountIn);

            // Calculate the minimum amount of ETH to receive, considering slippage tolerance
            uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
            return swapTokenForETHV3(_token, _amountIn, feeTier, amountOutMinimum, address(this));
        } else {
            revert("Invalid Uniswap version");
        }
    }

    function swapETHForToken(IERC20 _token, uint256 _ethAmount, string memory version, uint24 feeTier) external payable {
        // Calculate the minimum amount of tokens to receive, considering slippage tolerance
        if (keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("v2"))) {
            address[] memory path = new address[](2);
            path[0] = uniswapV2Router.WETH();
            path[1] = address(_token);
            uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_ethAmount, path);
            uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;
            swapETHForTokenV2(_token, _ethAmount, amountOutMinimum);
        } else if (keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("v3"))) {
            bytes memory path = abi.encodePacked(uniswapV2Router.WETH(), feeTier, address(_token));
            uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(path, _ethAmount);
            uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
            swapETHForTokenV3(_token, _ethAmount, feeTier, amountOutMinimum);
        } else {
            revert("Invalid Uniswap version");
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
        if (keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("v2"))) {
            address[] memory path = new address[](2);
            path[0] = address(_token);
            path[1] = uniswapV2Router.WETH();

            uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(_amount, path);
            uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;

            amountOut = swapTokenForETHV2(_token, _amount, amountOutMinimum, address(this));
            profitToETH += amountOut;
        } else if (keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("v3"))) {
            bytes memory pathV3 = abi.encodePacked(address(_token), feeTier, uniswapV2Router.WETH());
            uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(pathV3, _amount);
            uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;

            amountOut = swapTokenForETHV3(_token, _amount, feeTier, amountOutMinimum, address(this));
            profitToETH += amountOut;
        } else {
            revert("Invalid Uniswap version");
        }
    }

    function buyTokens(IERC20 _token, uint256 _amountOut, string memory version, uint24 feeTier) internal {
        if (keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("v2"))) {
            address[] memory path = new address[](2);
            path[0] = uniswapV2Router.WETH();
            path[1] = address(_token);
            uint256[] memory expectedAmountsIn = uniswapV2Router.getAmountsIn(_amountOut, path);
            if (profitToETH > expectedAmountsIn[1]) {
                uint256[] memory expectedAmountsOut = uniswapV2Router.getAmountsOut(expectedAmountsIn[1], path);
                uint256 amountOutMinimum = (expectedAmountsOut[1] * (10000 - slippageTolerance)) / 10000;
                swapETHForTokenV2(_token, expectedAmountsIn[1], amountOutMinimum);
            } else {
                uint256[] memory expectedAmountsOut = uniswapV2Router.getAmountsOut(profitToETH, path);
                uint256 amountOutMinimum = (expectedAmountsOut[1] * (10000 - slippageTolerance)) / 10000;
                swapETHForTokenV2(_token, profitToETH, amountOutMinimum);
            }
        } else if (keccak256(abi.encodePacked(version)) == keccak256(abi.encodePacked("v3"))) {
            bytes memory pathV3 = abi.encodePacked(uniswapV2Router.WETH(), feeTier, address(_token));
            uint256 expectedAmountIn = uniswapV3Quoter.quoteExactOutput(pathV3, _amountOut);
            if (profitToETH > expectedAmountIn) {
                uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(pathV3, expectedAmountIn);
                uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
                swapETHForTokenV3(_token, expectedAmountIn, feeTier, amountOutMinimum);
            } else {
                uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(pathV3, profitToETH);
                uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
                swapETHForTokenV3(_token, profitToETH, feeTier, amountOutMinimum);
            }
        } else {
            revert("Invalid Uniswap version");
        }
    }
}
