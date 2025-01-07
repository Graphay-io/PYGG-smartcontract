// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interface/IWETH.sol";
import { TokenInfo, Version } from "./Structs.sol";
import "./SwapOperationManager.sol";
import "./WhiteListManager.sol";

contract PYGGportfolioRebalancer is Ownable, Pausable, ERC20, SwapOperationManager, WhiteListManager {
    TokenInfo[] private portfolio;
    mapping(address => uint256) public ethDepositedFailed;

    uint16 private depositFee;
    uint16 private withdrawalFee;

    uint256 private totalFeesToETH;
    uint256 private totalFeesToWETH;

    bool public initialedTokens = false;

    event AddToken(address _tokens, uint256 targetPercentage);

    constructor(
        string memory _name,
        string memory _symbol,
        address _weth,
        address _uniswapV2Router,
        address _uniswapV3Router,
        address _uniswapV3Quoter
    )
        Ownable(msg.sender)
        ERC20(_name, _symbol)
        SwapOperationManager(_uniswapV2Router, _uniswapV3Router, _uniswapV3Quoter)
        WhiteListManager(address(owner()))
    {
        withdrawalFee = 100;
        depositFee = 100;
    }

    function initializeTokens(
        address[] calldata _tokens,
         uint256[] calldata _targetPercentages,
        Version[] calldata _versions,
        uint24[] calldata _feeTiers
    ) external onlyOwner {
        require(!initialedTokens, "Tokens already initialized");
        require(_tokens.length == _targetPercentages.length, "Mismatched lengths");

        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_targetPercentages[i] <= 10000, "Invalid percentage");
            totalPercentage += _targetPercentages[i];
             portfolio.push(TokenInfo({
                token: IERC20(_tokens[i]),
                targetPercentage: _targetPercentages[i],
                version: _versions[i],
                feeTier: _feeTiers[i]
            }));
        }
        require(totalPercentage == 10000, "Total percentage must be 10000");
        initialedTokens = true;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawAllToETH() external onlyOwner {
        uint256 totalETH = 0;
        uint256 totalWETH = 0;
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenBalance = tokenInfo.token.balanceOf(address(this));
            if (tokenBalance > 0) {
                try this.swapTokenForETH(tokenInfo.token, tokenBalance, tokenInfo.version, tokenInfo.feeTier, address(owner())) returns (uint256 ethReceived) {
                    if (tokenInfo.version == Version.V2) {
                        totalETH += ethReceived;
                    } else if(tokenInfo.version == Version.V3){
                        totalWETH += ethReceived;
                    }
                } catch  {}
            }
        }
    }

    function deposit() external payable onlyWhitelisted whenNotPaused {
        require(msg.value > 0, "Deposit amount must be greater than zero");

        uint256 fee = (msg.value * depositFee) / 10000;
        uint256 amountAfterFee = msg.value - fee;
        totalFeesToETH += fee;

        require(amountAfterFee > 0, "Amount after fee must be greater than zero");
        _mint(msg.sender, amountAfterFee);

        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 ethAmount = (amountAfterFee * tokenInfo.targetPercentage) / 10000;
            if (ethAmount > 0) {
                try this.swapETHForToken{value: calEthAmount}(tokenInfo.token, calEthAmount, tokenInfo.version, tokenInfo.feeTier) {} catch {
                    ethDepositedFailed[msg.sender] += calEthAmount;
                    failedSwaps.push(FailedSwap(msg.sender, tokenInfo.token, calEthAmount, tokenInfo.version, tokenInfo.feeTier));
                    userFailedSwaps[msg.sender]++;
                }
            }
        }
    }

    function withdraw(uint256 tokenAmount) external whenNotPaused {
        require(tokenAmount > 0, "Withdraw amount must be greater than zero");
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

        uint256 userShare = (tokenAmount * 10000) / totalSupply();
        _burn(msg.sender, tokenAmount);

        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenAmountToWithdraw = (tokenInfo.token.balanceOf(address(this)) * userShare) / 10000;
            if (tokenAmountToWithdraw > 0) {
                tokenInfo.token.transfer(msg.sender, tokenAmountToWithdraw);
            }
        }
    }

    function setFees(uint16 _depositFee, uint16 _withdrawalFee) external onlyOwner {
        require(_depositFee <= 10000, "Invalid deposit fee");
        require(_withdrawalFee <= 10000, "Invalid withdrawal fee");
        depositFee = _depositFee;
        withdrawalFee = _withdrawalFee;
    }

    function withdrawFeesByOwner(address _receiverFeeAddress) external onlyOwner {
        if (totalFeesToETH > 0) {
            (bool success, ) = _receiverFeeAddress.call{value: totalFeesToETH}("");
            require(success, "ETH transfer failed");
            totalFeesToETH = 0;
        }
    }

    function getPortfolioValue(uint256[] memory _tokenPrices) public view returns (uint256) {
        require(_tokenPrices.length == portfolio.length, "Mismatched prices length");
        uint256 totalValue = 0;
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenBalance = tokenInfo.token.balanceOf(address(this));
            uint256 tokenPrice = _tokenPrices[i];
            totalValue += tokenBalance * tokenPrice;
        }
        return totalValue;
    }

    function getAllTokens() external view returns (TokenInfo[] memory) {
        return portfolio;
    }
}
