// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct UserData {
    mapping(uint256 => uint256) balance; // weth balance of user in each round
    mapping(address => uint256) tShare;
    mapping(address => uint256) tShareOfATokenPortfo; // token share of the total portfo(user's share from a token in the whole contract portfo)
    uint256 tSharePortfo; // share of the user from total portfolio
    mapping(address => uint256) theTokenBalance;
    mapping(address => mapping(uint256 round => uint256)) tokenBalances; // token => round => user balance
    mapping(address => mapping(uint256 round => uint256)) tokenPricesETH; // token => round => price in ETH
    mapping(address => mapping(uint256 round => uint256)) tokenPricesUSD; // token => round => price in USD
    mapping(address => mapping(uint256 round => uint256)) initialUSDTPrices; // token => round => initial USDT price
    mapping(address => mapping(uint256 round => uint256)) initialUSDTPricesOne; // token => round => initial USDT price of 1 piece of the token
    mapping(address => mapping(uint256 round => uint256)) currntUSDTPricesOne; // token => round => initial USDT price of 1 piece of the token
    mapping(address token => mapping(address route => uint256 amount)) rebalancings;
    mapping(uint256 stage => mapping(address token => uint256 value)) tokenValue; // stage: initial(0) or current(1) > token > total value
    mapping(uint256 stage => uint256 value) value; // stage: initial(0) or current(1) > total value
    // address[] buyingTokens;
    address[] swapQueue; // Queue for tokens that exceeded slippage tolerance
    // address[] soldTokens;
    // address[] BougthTokens;
    uint256 wethValueFirst;
    uint256 usdtValueFirst;
    uint256 round;
}

struct ActivePools {
    address activeWethPool;
    address activeUsdPool;
    // address activeWethTokenPool;
    address tokenIn;
    address tokenOut;
    uint8 uniV;
}

struct Fees {
    uint16 depositFee;
    uint16 WithdrawFee;
}

struct MyTokenData {
    address path;
    address tokenIn;
    address tokenOut;
    uint256 usdValue;
    uint256 wethValue;
    uint8 uniV;
}

struct RebalancingData {
    mapping(address sellingToken => mapping(uint256 round => uint256 sellingAmount)) sellingTokens;
    mapping(address buyingToken => mapping(uint256 round => uint256 buyingAmount)) buyingTokens;
    uint256 round;
}

struct PortfoValue {
    uint256 totalInitValue;
    uint256 totalCurrentValue;
    mapping(address token => uint256 shareOfPortfo) tShares;
    mapping(address token => uint256 shareOfPortfo) tInitShares;
    mapping(address token => uint256 shareOfPortfo) tCurrentShares;
    mapping(address => uint256) initPrices; // token > initial usdtValue
    mapping(address => uint256) currentPrices; // token > current usdtValue
    mapping(address => uint256) currentPricesWeth; // weth > current wethValue
    address[] tokens;
    uint256[] tUsdt;
}
