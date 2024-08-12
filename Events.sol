// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PM5_Events {
    event UserAdded(address indexed user);
    event UserWhitelisted(address indexed account);
    event RemovedFromWhitelist(address indexed account);
    event TokensAdded(address[] addedTokens);
    event DepositReceived(address indexed user, uint256 amount);
    event FeeReceived(address indexed owner, uint256 amount);
    event FeesWithdrawn(address indexed owner, uint256 amount, string tokenType);
    event SwapSuccessful(
        address indexed user, uint256 wethAmountPerToken, int256 receivedTokenAmount, string tokenName, string uniswapV
    );
    event SwapFailed(address indexed user, uint256 amount, string tokenName, string reason);
    // event BoughtAmount(address indexed buyer, uint256 BoughtAmt, string tokenSymb, string uniV);
    // event UserDataCheck(address indexed buyer, address[] tokens, uint256 wethValueFirst, uint256 usdtValueFirst);
    // event GetPortfoTotalValueEvent(uint256[] vals, uint256 tValue);

    // event UserRound(uint256 userRound);
    // event trace(address indexed sender, uint256 amt, string line);
    // event trace4(address indexed sender, int256 amt, string line);
    event TokenData(address route, address tokenOut, uint256 usdVal, uint256 wethVal, uint8 uniV);
    event TokenDataBytes(bytes tokenData);
    event V3ETH(bool isV3);
    event PortfoTokenBalances(uint256 daiCount);
    event PortfoTokenPricesETH(uint256 daiETHPrice);
    event PortfoTokenInitialUSDTPrices(uint256 daiInitialUsdtPrice);
    event FundsRecieved(address indexed sender, uint256 ethAmount);
    event TokenSharesUpdated(bool status);

    event InitValuesSet(uint256 initUSD, address[] tokens, uint256[] tUSD);
    event CurrentValuesSet(uint256 currentUSD, address[] tokens, uint256[] tUSD);

    event TokensList(address[] list);
    event howMuch(address indexed sender, uint256 amt);
    event ShowDepositedTokensData(address[] tokenIn, address[] tokenOut);
    event handleWETHToTokenSwapEvent(address token, uint256 ethAmtPerToken, address tokenOut);
    event handleTokenToTokenSwapEvent(address token, uint256 userTokenBalance, address tokenOut);
    event AMTout(uint256 amtOut);
    event handleSwapEvent(uint256 amount, address tokenIn, address tokenOut, uint256 minAmtOut);
    event handleSwapEventAmtOut(uint256[] minAmtOut, address[] pairAddress);
    event UserTokenBalance(address token, uint256 round, uint256 tokenbalance);
    event WithdrawEvent(address user, int256 withAmt);
    event WithdrawEvent(address token, uint256 withAmt);
    event ShowTokensDataEvent(address[] pool, uint8[] uniV);
    event withdrawInKindEvent(address token, uint256 beforeWithAmt, uint256 withAmt, uint256 remained);
    event Balance(address sender, uint256 bal);
    event withdrawAllInKindEvent(address token, uint256 remained);
    event TokensWithdrawAllInKindEvent(address token, uint256 bal);
    // event InMemoryLength(uint256 len);
    // event InMemoryLength(address[] tokens);

    event WETHVALUE(uint256 wethVal);
    // event MyUsdtVALUE(uint256 usdtVal);
    event Pool(address pool);
    event PRICE(uint256 price);
    // event DoRebalance(address[] pool, uint8[] uniV);
    // event DoRebalance2(address[] pool, uint256[] shares);
    // event DoRebalance3(address token);

    event UserTokenBalanceRound(address user, address token, uint256 round, uint256 userTokenBalance);
    event UserTokenBalance(address user, address token, uint256 userTokenBalance);
    event UserTokensBalance(address user, address[] tokens, uint256[] userTokensBalance);
    event TOTALETH(uint256 Total, address admin, uint256 ContractBalance);
    event WethBalanceAdmin(uint256 wethBalance, address admin);

    event TokenRemoved(address tokens);
    event SQRTPriceX(uint256 SQRT);

    event Rebalanced(uint256 OccureTime);
}
