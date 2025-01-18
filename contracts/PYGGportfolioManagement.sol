// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IWETH.sol";
import "./interface/IPortfolioFactory.sol";
import { Basket, Version, SwapPath } from "./Structs.sol";
import "./SwapOperationManager.sol";
import "./lib/FeeCalculation.sol";

contract PYGGportfolioManagement is Ownable, ERC20, SwapOperationManager {
    using FeeCalculation for uint256;

    Basket[] private basket;

    uint256 public totalFeesWETH;
    uint16 public withdrawalFee;
    uint16 public depositFee;

    bool public initialedTokens = false;

    mapping(address => uint256) public ethDepositedFailed;

    address private factory;

    event Deposit(SwapPath _swapath, address _sender);
    event withdrawalToETH(uint256 _tokenAmount, SwapPath _swapath, address _receiver);
    event withdrawalInKind(uint256 _tokenAmount, address _receiver);

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
        setVaultContract(address(this));
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
            basket.push(Basket({
                token: IERC20(_tokens[i]),
                targetPercentage: _targetPercentages[i]
            }));
        }
        require(totalPercentage == 10000, "t=10000");
        initialedTokens = true;
    }

    function deposit(SwapPath calldata _swapath) external {
        require(initialedTokens, "initialize needed");
        require(_swapath.amountIn > 0, "!>0");
        
        (uint256 amountAfterFee, uint256 fee) = _swapath.amountIn.calculateAmountAfterFee(depositFee);
        totalFeesWETH += fee;

        require(amountAfterFee > 0, "!>0");
        TransferHelper.safeTransferFrom(address(uniswapV2Router.WETH()), msg.sender, address(this), _swapath.amountIn);
        TransferHelper.safeApprove(address(uniswapV2Router.WETH()), address(uniswapV3Router), _swapath.amountIn);
        TransferHelper.safeApprove(address(uniswapV2Router.WETH()), address(uniswapV2Router), _swapath.amountIn);
        
        _mint(msg.sender, amountAfterFee);

        for (uint256 i = 0; i < basket.length; i++) {
            Basket storage _basket = basket[i];
            uint256 ethAmount = (amountAfterFee * _basket.targetPercentage) / 10000;
            require(ethAmount <= amountAfterFee, "!ethAmount<=amountfee");
            if (ethAmount > 0) {
                this.swapTokenForToken(_basket.token, ethAmount, _swapath.directions[i].version, address(this), _swapath.directions[i].path);
            }
        }
        emit Deposit(_swapath, address(msg.sender));
    }

    function withdrawToETH(uint256 tokenAmount, SwapPath calldata _swapath) external {
        require(initialedTokens, "initialize needed");
        require(tokenAmount > 0, ">0");
        require(this.balanceOf(msg.sender) >= tokenAmount, "!Insufficient");

        uint256 userShare = tokenAmount.calculatePercentage(totalSupply());

        address WETH9 = uniswapV2Router.WETH();
        uint256 totalWETH = 0;
        for (uint256 i = 0; i < basket.length; i++) {
            Basket storage _basket = basket[i];
            uint256 tokenAmountToWithdraw =  (_basket.token.balanceOf(address(this)) * userShare) / 10000;
            totalWETH = this.swapTokenForToken(_basket.token, tokenAmountToWithdraw, _swapath.directions[i].version, address(this), _swapath.directions[i].path);
        }

        _burn(msg.sender, tokenAmount);

        if(totalWETH > 0){
            (uint256 amountAfterFeeWETH, uint256 feeWETH) = totalWETH.calculateAmountAfterFee(withdrawalFee);
            totalFeesWETH += feeWETH;
            IWETH(WETH9).transfer(msg.sender, amountAfterFeeWETH);
        }
        emit withdrawalToETH(tokenAmount, _swapath, address(msg.sender));
    }

    function withdrawInKind(uint256 tokenAmount, SwapPath memory _swapath) external {
        require(initialedTokens, "initialize needed");
        require(tokenAmount > 0, "W>0");
        require(balanceOf(msg.sender) >= tokenAmount, "!balance");

        uint256 userShare = tokenAmount.calculatePercentage(totalSupply());
        _burn(msg.sender, tokenAmount);

        for (uint256 i = 0; i < basket.length; i++) {
            Basket storage _basket = basket[i];
            uint256 tokenAmountToWithdraw = (_basket.token.balanceOf(address(this)) * userShare) / 10000;
            require(tokenAmountToWithdraw > 0, "!>0");
            (uint256 amountAfterFee, uint256 feeWETH) = tokenAmountToWithdraw.calculateAmountAfterFee(withdrawalFee);
            _basket.token.transfer(msg.sender, amountAfterFee);
            try this.swapTokenForToken(_basket.token, feeWETH, _swapath.directions[i].version, address(this), _swapath.directions[i].path) returns (uint256 ethReceived) {
                totalFeesWETH += ethReceived;
            } catch {}
        }

        emit withdrawalInKind(tokenAmount, address(msg.sender));
    }

    function withdrawFeesByOwner(address _receiverFeeAddress) external onlyOwner {
        require(_receiverFeeAddress != address(0), "Invalid receiver address");

        if (totalFeesWETH > 0) {
        // Ensure the contract has sufficient WETH balance
        address WETH = uniswapV2Router.WETH();
        uint256 contractWETHBalance = ERC20(WETH).balanceOf(address(this));
        require(contractWETHBalance >= totalFeesWETH, "Insufficient WETH balance");

        // Transfer WETH to the receiver address
        bool success = ERC20(WETH).transfer(_receiverFeeAddress, totalFeesWETH);
        require(success, "WETH transfer failed");

        // Reset the fee tracker
        totalFeesWETH = 0;
        }
    }

    function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
        _setSlippageTolerance(_slippageTolerance);
    }

    function getBasket() external view returns (Basket[] memory) {
        return basket;
    }
}
