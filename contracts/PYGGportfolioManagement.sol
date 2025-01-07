// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IWETH.sol";
import "./interface/IPortfolioFactory.sol";
import { TokenInfo, Version, SwapPath } from "./Structs.sol";
import "./SwapOperationManager.sol";

contract PYGGportfolioManagement is Ownable, ERC20, SwapOperationManager {
    
    TokenInfo[] private tokens;

    uint256 private totalFeesWETH;
    uint16 public withdrawalFee;
    uint16 public depositFee;

    bool public initialedTokens = false;

    mapping(address => uint256) public ethDepositedFailed;

    address private factory;

    event AddToken(address _tokens, uint256 targetPercentage);

    constructor(
        string memory _name,
        string memory _symbol,
        address _uniswapV2Router,
        address _uniswapV3Router,
        address _uniswapV3Quoter
    )
        Ownable(msg.sender)
        ERC20(_name, _symbol)
        SwapOperationManager(_uniswapV2Router, _uniswapV3Router, _uniswapV3Quoter)
    {
        factory = msg.sender;
    }

    function initializeTokens(
        address[] calldata _tokens,
        uint256[] calldata _targetPercentages,
        uint16 _withdrawalFee,
        uint16 _depositFee
    ) external onlyOwner {
        require(!initialedTokens, "initialized");
        require(_tokens.length == _targetPercentages.length, "Mismatched lengths");
        withdrawalFee = _withdrawalFee;
        depositFee = _depositFee;
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_targetPercentages[i] <= 10000, "InvalidPercentage");
            totalPercentage += _targetPercentages[i];
             tokens.push(TokenInfo({
                token: IERC20(_tokens[i]),
                targetPercentage: _targetPercentages[i]
            }));
        }
        require(totalPercentage == 10000, "t=10000");
        initialedTokens = true;
    }

    function deposit(bytes memory _path) external payable {
        (SwapPath memory _swapath) = abi.decode(_path, (SwapPath));
        require(_swapath.amountIn > 0, "!>0");

        uint256 fee = (_swapath.amountIn * depositFee) / 10000;
        uint256 amountAfterFee = _swapath.amountIn - fee;
        totalFeesWETH += fee;

        require(amountAfterFee > 0, "!>0");
        _mint(msg.sender, amountAfterFee);

        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInfo storage tokenInfo = tokens[i];
            uint256 ethAmount = (amountAfterFee * tokenInfo.targetPercentage) / 10000;
            require(ethAmount <= amountAfterFee, "!ethAmount<=amountfee");
            if (ethAmount > 0) {
                try this.swapTokenForToken(tokenInfo.token, ethAmount, _swapath.version, msg.sender, _swapath.path) {} catch {
                    ethDepositedFailed[msg.sender] += ethAmount;
                    failedSwaps.push(FailedSwap(msg.sender, tokenInfo.token, ethAmount));
                    userFailedSwaps[msg.sender]++;
                }
            }
        }
    }

    function withdrawToETH(uint256 tokenAmount, bytes memory _path) external {
        require(tokenAmount > 0, ">0");
        require(this.balanceOf(msg.sender) >= tokenAmount, "!Insufficient");
        (SwapPath memory _swapath) = abi.decode(_path, (SwapPath));

        uint256 percentage = (tokenAmount * 10000) / totalSupply();

        address WETH9 = uniswapV2Router.WETH();
        uint256 totalWETH = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInfo storage tokenInfo = tokens[i];
            uint256 tokenAmountToWithdraw = (tokenInfo.token.balanceOf(address(this)) * percentage) / 10000;
                try this.swapTokenForToken(tokenInfo.token, tokenAmountToWithdraw, _swapath.version, msg.sender, _swapath.path) returns (uint256 ethReceived ) {
                    totalWETH += ethReceived;
                } catch {}
        }

        _burn(msg.sender, tokenAmount);

        if(totalWETH > 0){
            uint256 feeWETH = (totalWETH * withdrawalFee) / 10000;
            uint256 amountAfterFeeWETH = totalWETH - feeWETH;
            totalFeesWETH += feeWETH;
            IWETH(WETH9).transfer(msg.sender, amountAfterFeeWETH);
        }
        // emit Withdrawn(msg.sender, totalETH, percentage);
    }

    function withdrawInKind(uint256 tokenAmount) external {
        require(tokenAmount > 0, "W>0");
        require(balanceOf(msg.sender) >= tokenAmount, "!balance");

        uint256 userShare = (tokenAmount * 10000) / totalSupply();
        _burn(msg.sender, tokenAmount);

        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInfo storage tokenInfo = tokens[i];
            uint256 tokenAmountToWithdraw = (tokenInfo.token.balanceOf(address(this)) * userShare) / 10000;
            if (tokenAmountToWithdraw > 0) {
                tokenInfo.token.transfer(msg.sender, tokenAmountToWithdraw);
            }
        }
    }

    function withdrawFeesByOwner(address _receiverFeeAddress) external onlyOwner {
        if (totalFeesWETH > 0) {
            (bool success, ) = _receiverFeeAddress.call{value: totalFeesWETH}("");
            require(success, "transferFailed");
            totalFeesWETH = 0;
        }
    }

    function getAllTokens() external view returns (TokenInfo[] memory) {
        return tokens;
    }
}
