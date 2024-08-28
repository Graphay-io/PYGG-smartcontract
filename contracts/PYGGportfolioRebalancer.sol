// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interface/IUniswapV2Router02.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interface/IUniswapV3Quoter.sol";
import "./interface/IWETH.sol";
import { TokenInfo } from "./Structs.sol";
import "./SwapOperationManager.sol";
import "./WhiteListManager.sol";


contract PYGGportfolioRebalancer is Ownable, Pausable, ERC20, SwapOperationManager, WhiteListManager  {

    TokenInfo[] private portfolio;
    mapping(address => uint256) public ethDepositedFailed;

    uint256 private depositFee; // Fee in basis points (e.g., 100 = 1%)
    uint256 private withdrawalFee; // Fee in basis points (e.g., 100 = 1%)
    uint256 private totalFeesToETH;
    uint256 private totalFeesToWETH;
    bool public initialedTokens = false;

    bytes32 private constant VERSION_V2 = keccak256(abi.encodePacked("v2"));
    bytes32 private constant VERSION_V3 = keccak256(abi.encodePacked("v3"));

    // event Deposited(address indexed user, uint256 amount, uint256 shares, string version);
    // event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    // event Rebalanced(uint256 timestamp);
    // event Whitelisted(address indexed user, bool isWhitelisted);
    // event SwapFailed(address indexed user, IERC20 token, uint256 amount, string version);
    // event SlippageToleranceChanged(uint256 newSlippageTolerance);
    event AddToken(address _tokens, uint256 targetPercentage, string verision, uint24 feeTier);

    constructor(address _uniswapV2Router, address _uniswapV3Router, address _uniswapV3Quoter)
        Ownable(msg.sender) ERC20("PYGGETH", "PETH") SwapOperationManager(_uniswapV2Router, _uniswapV3Router, _uniswapV3Quoter)
        WhiteListManager()
    {
        withdrawalFee = 100;
        depositFee = 100;
    }

    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }
    
    function unpause() external onlyOwner() {
        _unpause();
        emit Unpaused(msg.sender);
    }

    function withdrawAllToETH() external onlyOwner {
        uint256 totalETH = 0;
        uint256 totalWETH = 0;
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenBalance = tokenInfo.token.balanceOf(address(this));
            try this.swapTokenForETH(tokenInfo.token, tokenBalance, tokenInfo.version, tokenInfo.feeTier, address(owner())) returns (uint256 ethReceived) {
                if (keccak256(abi.encodePacked(tokenInfo.version)) == VERSION_V2) {
                    totalETH += ethReceived;
                } else if(keccak256(abi.encodePacked(tokenInfo.version)) == VERSION_V3){
                    totalWETH += ethReceived;
                }
            } catch  {}
        }
    }

    function withdrawWholeAllInKind() external onlyOwner {
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenBalance = tokenInfo.token.balanceOf(address(this));
            tokenInfo.token.transfer(msg.sender, tokenBalance);
        }
    }

    function setFees(uint256 _depositFee, uint256 _withdrawalFee) external onlyOwner {
        require(_depositFee <= 10000, "!dfee");
        require(_withdrawalFee <= 10000, "!wfee");
        depositFee = _depositFee;
        withdrawalFee = _withdrawalFee;
    }

    function withdrawFeesByOwner(address _receiverFeeAddress) external onlyOwner {
        if(totalFeesToETH > 0){
            (bool success, ) = _receiverFeeAddress.call{value: totalFeesToETH}("");
            require(success, "FAILEDETH");
            totalFeesToETH = 0;
        }
        if(totalFeesToWETH > 0){
            address WETH9 = getWETHaddress();
            IWETH(WETH9).transfer(_receiverFeeAddress, totalFeesToWETH);
            totalFeesToWETH = 0;
        }
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
        require(!initialedTokens, "the contract has initialized");
        require(
            _tokens.length == _targetPercentages.length && 
            _tokens.length == _versions.length && 
            _tokens.length == _feeTiers.length, 
            "!Misslengths"
        );
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_targetPercentages[i] <= 10000, "!percentage");
            totalPercentage += _targetPercentages[i];
            portfolio.push(TokenInfo({
                token: IERC20(_tokens[i]),
                targetPercentage: _targetPercentages[i],
                version: _versions[i],
                feeTier: _feeTiers[i]
            }));
            emit AddToken(_tokens[i], _targetPercentages[i], _versions[i], _feeTiers[i]);
        }
        require(totalPercentage == 10000, "total percentage should be 10000");
        initialedTokens = true;
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


    function deposit() external payable onlyWhitelisted whenNotPaused {
        require(msg.value > 0, "AMG");

        uint256 fee = (msg.value * depositFee) / 10000;
        uint256 amountAfterFee = msg.value - fee;
        totalFeesToETH += fee;

        require(amountAfterFee > 0, "Amount after fee must be greater than zero");
        _mint(msg.sender, amountAfterFee);
        // emit Deposited(msg.sender, amountAfterFee, amountAfterFee, "N/A");

        // Swap ETH to portfolio tokens
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 calEthAmount = (amountAfterFee * tokenInfo.targetPercentage) / 10000;
            require(calEthAmount <= amountAfterFee, "calETH<=amountfee");
            // this.swapETHForToken{value: calEthAmount}(tokenInfo.token, calEthAmount, tokenInfo.version, tokenInfo.feeTier);
            try this.swapETHForToken{value: calEthAmount}(tokenInfo.token, calEthAmount, tokenInfo.version, tokenInfo.feeTier) {} catch {
                ethDepositedFailed[msg.sender] += calEthAmount;
                failedSwaps.push(FailedSwap(msg.sender, tokenInfo.token, calEthAmount, tokenInfo.version, tokenInfo.feeTier));
                userFailedSwaps[msg.sender]++;
                // emit SwapFailed(msg.sender, tokenInfo.token, calEthAmount, tokenInfo.version);
            }
            // Adjust amountAfterFee to reflect the used ETH
        }
    }

    function withdrawToETH(uint256 tokenAmount) external whenNotPaused {
        require(tokenAmount > 0, ">0");
        require(this.balanceOf(msg.sender) >= tokenAmount, "!Insufficient");

        uint256 percentage = (tokenAmount * 10000) / totalSupply();

        address WETH9 = uniswapV2Router.WETH();
        uint256 totalETH = 0;
        uint256 totalWETH = 0;
        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenAmountToWithdraw = (tokenInfo.token.balanceOf(address(this)) * percentage) / 10000;
                try this.swapTokenForETH(tokenInfo.token, tokenAmountToWithdraw, tokenInfo.version, tokenInfo.feeTier, address(this)) returns (uint256 ethReceived ) {
                    if(keccak256(abi.encodePacked(tokenInfo.version)) == keccak256(abi.encodePacked("v3"))){
                        totalWETH+= ethReceived;
                    } else {
                        totalETH += ethReceived;
                    }
                } catch {}
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
        // emit Withdrawn(msg.sender, totalETH, percentage);
    }

    function withdraw(uint256 tokenAmount) external whenNotPaused {
        require(tokenAmount > 0, ">0");
        require(this.balanceOf(msg.sender) >= tokenAmount, "Insufficient");

        uint256 userShare = (tokenAmount * 10000) / totalSupply();

        for (uint256 i = 0; i < portfolio.length; i++) {
            TokenInfo storage tokenInfo = portfolio[i];
            uint256 tokenAmountToWithdraw = (tokenInfo.token.balanceOf(address(this)) * userShare) / 10000;
            uint256 fee = (tokenAmountToWithdraw * withdrawalFee) / 10000;
            uint256 amountAfterFee = tokenAmountToWithdraw - fee;
            tokenInfo.token.transfer(msg.sender, amountAfterFee);
            try this.swapTokenForETH(tokenInfo.token, fee, tokenInfo.version, tokenInfo.feeTier, address(this)) returns (uint256 ethReceived) {
                if(keccak256(abi.encodePacked(tokenInfo.version)) == VERSION_V3){
                    totalFeesToWETH += ethReceived;
                } else {
                    totalFeesToETH += ethReceived;
                }
            } catch {}
        }

        _burn(msg.sender, tokenAmount);
        uint256 failedETHsUser = (ethDepositedFailed[msg.sender] * userShare) / 10000;
        uint256 totalTransferAmount = failedETHsUser;
        if(totalTransferAmount > 0){
            (bool success, ) = msg.sender.call{value: totalTransferAmount}("");
            require(success, "TR");
        }
        // emit Withdrawn(msg.sender, userShare, userShare);
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

    function getAllTokens() external view returns (TokenInfo[] memory) {
        return portfolio;
    }

    // function needsRebalance(uint256[] memory _tokenPrices) external view returns (bool) {
    //     require(_tokenPrices.length == portfolio.length, "!PL");

    //     uint256 totalValue = getPortfolioValue(_tokenPrices);
    //     require(totalValue > 0, "TV>0");

    //     for (uint256 i = 0; i < portfolio.length; i++) {
    //         TokenInfo storage tokenInfo = portfolio[i];
    //         uint256 currentPrice = _tokenPrices[i] * tokenInfo.token.balanceOf(address(this));
    //         require(currentPrice > 0, "CP>0");

    //         uint256 shareTokenOfPortfolio = (currentPrice * 10000) / totalValue;

    //         if (shareTokenOfPortfolio > tokenInfo.targetPercentage) {
    //             return true;
    //         } else if (shareTokenOfPortfolio < tokenInfo.targetPercentage) {
    //             return true;
    //         }
    //     }

    // function rebalance(uint256[] memory _tokenPrices)
    //     external
    //     onlyOwner whenNotPaused
    // {
    //     uint256 totalValue = getPortfolioValue(_tokenPrices);
    //     require(totalValue > 0, "Total value must be greater than zero");

    //     for (uint256 i = 0; i < portfolio.length; i++) {
    //         TokenInfo storage tokenInfo = portfolio[i];
    //         uint256 currentValue = _tokenPrices[i] * tokenInfo.token.balanceOf(address(this));
    //         uint256 targetValue = (totalValue * tokenInfo.targetPercentage) / 10000;

    //         if (currentValue > targetValue) {
    //             uint256 amountToSell = (currentValue - targetValue) / _tokenPrices[i];
    //             sellTokens(tokenInfo.token, amountToSell, tokenInfo.version, tokenInfo.feeTier);
    //         } else if (currentValue < targetValue) {
    //             uint256 amountTobuy = (targetValue - currentValue) / _tokenPrices[i];
    //             buyTokens(tokenInfo.token, amountTobuy, tokenInfo.version, tokenInfo.feeTier);
    //         }
    //     }
    // }
}
