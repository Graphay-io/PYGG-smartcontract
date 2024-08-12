// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./TokenManager.sol";

contract PYGGRED is TokenManager, ERC20 {
    uint256 public depositFee; // Fee in basis points (e.g., 100 = 1%)
    uint256 public withdrawalFee; // Fee in basis points (e.g., 100 = 1%)
    uint256 public totalFeesToETH;
    uint256 public totalFeesToWETH;

    mapping(address => bool) public whitelist;
    mapping(address => uint256) public ethDepositedFailed;

    event Deposited(address indexed user, uint256 amount, uint256 shares, string version);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);

    constructor(
        address _uniswapV2Router,
        address _uniswapV3Router,
        address _uniswapV3Quoter
    ) TokenManager(_uniswapV2Router, _uniswapV3Router, _uniswapV3Quoter) ERC20("PYGGETH", "PETH") {
        whitelist[msg.sender] = true;
        withdrawalFee = 100;
        depositFee = 100;
    }

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "!WHT");
        _;
    }

    function setFees(uint256 _depositFee, uint256 _withdrawalFee) external onlyOwner {
        require(_depositFee <= 10000, "!dfee");
        require(_withdrawalFee <= 10000, "!wfee");
        depositFee = _depositFee;
        withdrawalFee = _withdrawalFee;
    }

    function deposit() external payable onlyWhitelisted whenNotPaused {
        require(msg.value > 0, "AMG");

        uint256 fee = (msg.value * depositFee) / 10000;
        uint256 amountAfterFee = msg.value - fee;
        totalFeesToETH += fee;

        require(amountAfterFee > 0, "Amount after fee must be greater than zero");
        _mint(msg.sender, amountAfterFee);
        emit Deposited(msg.sender, amountAfterFee, amountAfterFee, "N/A");

        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 calEthAmount = (amountAfterFee * tokenInfo.targetPercentage) / 10000;
            require(calEthAmount <= amountAfterFee, "calETH<=amountfee");
            try this.swapETHForToken{value: calEthAmount}(tokenInfo.token, calEthAmount, tokenInfo.version, tokenInfo.feeTier) {} catch {
                ethDepositedFailed[msg.sender] += calEthAmount;
                // Add failed swap handling here if needed
            }
        }
    }

    function withdrawToETH(uint256 tokenAmount) external whenNotPaused {
        require(tokenAmount > 0, ">0");
        require(this.balanceOf(msg.sender) >= tokenAmount, "!Insufficient");

        uint256 percentage = (tokenAmount * 10000) / totalSupply();

        require(percentage > 0 && percentage <= 10000, "0&10000");
        address WETH9 = uniswapV2Router.WETH();
        uint256 totalETH = 0;
        uint256 totalWETH = 0;
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenAmountToWithdraw = (tokenInfo.token.balanceOf(address(this)) * percentage) / 10000;
            uint256 ethReceived = this.swapTokenForETH(tokenInfo.token, tokenAmountToWithdraw, tokenInfo.version, tokenInfo.feeTier);
            if(keccak256(abi.encodePacked(tokenInfo.version)) == keccak256(abi.encodePacked("v3"))){
                totalWETH+= ethReceived;
            } else {
                totalETH += ethReceived;
            }
        }
        _burn(msg.sender, tokenAmount);
        if(totalWETH > 0){
            uint256 feeWETH = (totalWETH * withdrawalFee) / 10000;
            uint256 amountAfterFeeWETH = totalWETH - feeWETH;
            totalFeesToWETH += feeWETH;
            IWETH(WETH9).transfer(msg.sender, amountAfterFeeWETH);
        }
        if(totalETH > 0){
            uint256 feeETH = (totalETH * withdrawalFee) / 10000;
            uint256 amountAfterFee = totalETH - feeETH;
            totalFeesToETH += feeETH;
            uint256 failedETHsUser = ethDepositedFailed[msg.sender];
            uint256 totalTransferAmount = failedETHsUser + amountAfterFee;
            (bool success, ) = msg.sender.call{value: totalTransferAmount}("");
            require(success, "ETH transfer failed");
        }
        emit Withdrawn(msg.sender, totalETH, percentage);
    }

    function withdraw(uint256 tokenAmount) external whenNotPaused {
        require(tokenAmount > 0, ">0");
        require(this.balanceOf(msg.sender) >= tokenAmount, "Insufficient");

        uint256 userShare = (tokenAmount * 10000) / totalSupply();

        require(userShare > 0 && userShare <= 10000, "0&10000");

        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenAmountToWithdraw = (tokenInfo.token.balanceOf(address(this)) * userShare) / 10000;
            uint256 fee = (tokenAmountToWithdraw * withdrawalFee) / 10000;
            uint256 amountAfterFee = tokenAmountToWithdraw - fee;
            tokenInfo.token.transfer(msg.sender, amountAfterFee);
            if (keccak256(abi.encodePacked(tokenInfo.version)) == VERSION_V2) {
                address[] memory path = new address[](2);
                path[0] = address(tokenInfo.token);
                path[1] = uniswapV2Router.WETH();
                uint256[] memory expectedAmounts = uniswapV2Router.getAmountsOut(fee, path);
                uint256 amountOutMinimum = (expectedAmounts[1] * (10000 - slippageTolerance)) / 10000;
                totalFeesToETH += swapTokenForETHV2(tokenInfo.token, fee, amountOutMinimum, address(this));
            } else if (keccak256(abi.encodePacked(tokenInfo.version)) == VERSION_V3) {
                bytes memory path = abi.encodePacked(address(tokenInfo.token), tokenInfo.feeTier, uniswapV2Router.WETH());
                uint256 expectedAmountOut = uniswapV3Quoter.quoteExactInput(path, fee);
                uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageTolerance)) / 10000;
                totalFeesToWETH += swapTokenForETHV3(tokenInfo.token, fee, tokenInfo.feeTier, amountOutMinimum, address(this));
            } else {
                revert("Invalid Uniswap version");
            }
        }

        _burn(msg.sender, tokenAmount);
        uint256 failedETHsUser = (ethDepositedFailed[msg.sender] * userShare) / 10000;
        uint256 totalTransferAmount = failedETHsUser;
        if(totalTransferAmount > 0){
            (bool success, ) = msg.sender.call{value: totalTransferAmount}("");
            require(success, "TR");
        }
        emit Withdrawn(msg.sender, userShare, userShare);
    }

    function setWhitelist(address _user, bool _status) external onlyOwner {
        whitelist[_user] = _status;
    }

    function withdrawFeesByOwner(address _receiverFeeAddress) external onlyOwner {
        if(totalFeesToETH > 0){
            (bool success, ) = _receiverFeeAddress.call{value: totalFeesToETH}("");
            require(success, "FAILEDETH");
            totalFeesToETH = 0;
        }
        if(totalFeesToWETH > 0){
            address WETH9 = uniswapV2Router.WETH();
            IWETH(WETH9).transfer(_receiverFeeAddress, totalFeesToWETH);
        }
    }
}
