// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./UniPrice.sol";
import "./UniSwap_pm5.sol";
import {IWETH} from "./IWETH.sol";
import {PM5_Events} from "./Events.sol";
import "v2-periphery/interfaces/IUniswapV2Router02.sol";
import "v3-periphery/interfaces/IQuoter.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UserData, Fees, ActivePools, RebalancingData, PortfoValue} from "./Structs.sol";

/// @title The Portfolio Manager System
/// @author Bahador Gh.
/// @notice The Portfolio Manager for trade management
contract PM5 is ReentrancyGuard, PM5_Events, Pausable, AccessControl {
    // using UniswapPriceLibrary for uint256;
    // using UniswapSwapLibrary for uint256;
    using UniswapSwapLibrary for UniswapSwapLibrary.SwapParams;
    using UniswapSwapLibrary for UniswapSwapLibrary.SwapV3Params;
    using ArrayElemenetRemover for address[];

    uint16 constant MAX_FEE_PERCENT = 300; // 3%
    address immutable WETH; // WETH token address polygon
    address constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F; // USDT token address polygon
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; // USDC token address polygon
    address constant UNISWAP_V2_ROUTER = 0xedf6066a2b290C185783862C7F4776A2C8077AD1; // Uniswap V2 Router address polygon
    address private constant UNISWAP_V3_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant UNISWAP_V3_Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    IUniswapV2Router02 private immutable uniswapV2Router;
    IUniswapV3Factory constant uniswapV3Factory = IUniswapV3Factory(UNISWAP_V3_Factory);

    address constant QUOTER_ADDRESS = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6; // QUOTER_ADDRESS etehreum and polygon
    IQuoter constant quoter = IQuoter(QUOTER_ADDRESS);
    // address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH token address ethereum
    // address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT token address ethereum
    // address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router address ethereum

    IWETH immutable WETH9;
    uint256 constant SFACTOR = 10000;

    bytes32 constant WHITELISTED_ROLE = keccak256("whitelisted");
    bytes32 ADMIN_ROLE = keccak256("admin");

    uint16 startFee = 100; // 1%
    address admin;
    address[] tokens;
    address[] swapQueue;
    address[] userAddresses;
    uint256 slippageTolerance = 1000; // 10%
    // uint256 priceDifferenceThreshhold = 500; // 5%
    uint256 recoveryBalance;
    uint256 accumulatedETHFees;

    mapping(address => bool) isUserAdded;
    mapping(address => UserData) public users;
    mapping(address => bool) Whitelisted;
    mapping(address => PortfoValue) portfoValues;

    Fees feeData;
    // MyTokenData[] tokenDataArray;

    enum RebalancingState {
        NONE,
        BUYING,
        SELLING
    }

    enum FeeDirection {
        None,
        Deposit,
        Withdraw
    }

    RebalancingState rebState;
    FeeDirection feeDirection;

    mapping(address token => ActivePools) activePools; // token > ActivePools[activeWethPool, activeUsdPool]

    constructor() {
        admin = msg.sender;
        uniswapV2Router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        WETH = uniswapV2Router.WETH();
        WETH9 = IWETH(WETH);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        feeData = Fees({depositFee: startFee, WithdrawFee: startFee});
    }

    /* ================= external functions    ================= */

    /// @notice Admin will enter token addresses
    /// @dev Only callable by addresses belong to ADMIN_ROLE
    /// @param _tokens address of erc20 tokens
    function addTokens(address[] calldata _tokens) external onlyRole(ADMIN_ROLE) {
        // address[] memory addedTokens = new address[](_tokens.length);
        for (uint256 i; i < _tokens.length; i++) {
            tokens.push(_tokens[i]);
        }
        // emit TokensAdded(tokens);
    }

    /// @notice Updating the fee occuring during deposit/withdraw
    /// @param depositFee new deposit fee (in bps, ex: 100 means 1%)
    /// @param WithdrawFee new withdraw fee (in bps, ex: 100 means 1%)
    function setFeeData(uint8 depositFee, uint8 WithdrawFee) external onlyRole(ADMIN_ROLE) {
        require((depositFee <= MAX_FEE_PERCENT) && (WithdrawFee <= MAX_FEE_PERCENT), "S3"); // S3 > Set fee <= 3%
        Fees storage theFee = feeData;
        if (depositFee == 0) {
            theFee.WithdrawFee = WithdrawFee;
        } else if (WithdrawFee == 0) {
            theFee.depositFee = depositFee;
        } else {
            theFee.depositFee = depositFee;
            theFee.WithdrawFee = WithdrawFee;
        }
    }

    function withdrawAccumulatedFees() external onlyRole(ADMIN_ROLE) nonReentrant {
        if (accumulatedETHFees > 0) {
            uint256 ethFees = accumulatedETHFees;
            accumulatedETHFees = 0;
            IERC20(WETH).transfer(admin, ethFees);
            emit FeesWithdrawn(admin, ethFees, "ETH");
        }
    }

    /// @notice Depositing backup funds to prevent lack of buying in case of rebalance
    /// @param wethAmount eth amount depositing
    function depositRecoveryBalance(uint256 wethAmount) external payable onlyRole(ADMIN_ROLE) {
        if (msg.value > 0) {
            WETH9.deposit{value: msg.value}();
            bool success = WETH9.transfer(address(this), msg.value);
            require(success, "DE"); // DE> deposit error
        }
        // note: removed due contract size limit
        // require(WETH9.balanceOf(address(this)) > wethAmount, "Lack of deposit amount");
        // require(msg.value == 0 || msg.value == wethAmount, "Wrong amount sent");
        recoveryBalance += wethAmount;
    }

    /// @notice Setting the slippage tolerance of the swap
    /// @param _slippageTolerance the slippage tolerance in bps (default: 10000 means 10%)
    function updateSlippageTolerance(uint256 _slippageTolerance) external onlyRole(ADMIN_ROLE) {
        slippageTolerance = _slippageTolerance;
    }

    function removeUser(uint256 index) external {
        userAddresses.removeElement(index);
    }

    /// @notice User can withdraw all his erc20 tokenBalances from the portfolio
    function withdrawAllInKind() external onlyRole(WHITELISTED_ROLE) whenNotPaused nonReentrant {
        UserData storage user = users[msg.sender];
        address[] memory tokensInMemory = tokens;
        uint256 fee;
        // uint256 _feeAmount = feeData.depositFee;
        for (uint256 i; i < tokensInMemory.length; i++) {
            uint256 tokenBalance = _userTokenBalance(msg.sender, tokensInMemory[i]);
            // uint256 tokenBalance = user.tokenBalances[tokensInMemory[i]][_round];
            if (tokenBalance == 0) continue;
            // require(tokenBalance > 0, "Insufficient token balance");
            fee = _calculateFee(tokenBalance, FeeDirection.Withdraw);
            // fee = (tokenBalance * _feeAmount) / SFACTOR;
            // Update the user's token balance
            for (uint256 j = 1; j <= user.round; j++) {
                user.tokenBalances[tokensInMemory[i]][j] = 0;
                user.theTokenBalance[tokensInMemory[i]] = 0;
            }

            // Transfer the specified amount of tokens to the user
            IERC20(tokensInMemory[i]).transfer(msg.sender, tokenBalance - fee);
            IERC20(tokensInMemory[i]).transfer(admin, fee);
            emit withdrawAllInKindEvent(tokensInMemory[i], tokenBalance - fee);
        }
        _updateAllUserBalances();
    }

    /// @notice Swapping all the user's funds into WETH and transferring to the user with WHITELISTED_ROLE cdredentials
    /// @param tokensData tokens data
    /// @param percentage withdrawal percentage of user's total funds
    function userWithdrawWholeFundWETH(bytes memory tokensData, uint256 percentage)
        external
        onlyRole(WHITELISTED_ROLE)
        whenNotPaused
        nonReentrant
    {
        // withdraw all tokens in user's portfolio
        // UserData storage user = users[admin];
        require(percentage > 0 && percentage <= 100, "IP"); // IP > Invalid percentage
        uint256 totalETH = 0;
        (address[] memory pool,, uint8[] memory uniV) = _getTokensData(tokensData);
        (address[] memory _tokens_, uint256[] memory _balances_) = userTokensBalance(msg.sender);
        (uint256[] memory values, uint256 totalValue) = _getPortfoTotalValue();
        uint256 withdrawValue = ((totalValue * percentage) * SFACTOR) / (100 * SFACTOR);
        // uint256 bps = percentage * 100;
        for (uint256 i; i < _tokens_.length; i++) {
            uint256 tokenValue = ((values[i] * _balances_[i]) * SFACTOR) / (100 * SFACTOR);
            // uint256 tokenAmount = (_balances_[i] * bps) / SFACTOR;
            uint256 tokenAmount = ((_balances_[i] * percentage) * SFACTOR) / (100 * SFACTOR);
            if (tokenValue > withdrawValue) {
                int256 ethAmountRecieved =
                    _handleSwap(users[msg.sender], tokenAmount, pool[i], _tokens_[i], WETH, uniV[i] == 3 ? true : false);
                for (uint256 j = 1; j <= users[msg.sender].round; j++) {
                    users[msg.sender].tokenBalances[_tokens_[i]][j] -= tokenAmount;
                }

                users[msg.sender].theTokenBalance[_tokens_[i]] -= tokenAmount;
                totalETH += uint256(ethAmountRecieved);
            } else {
                int256 ethAmountRecieved =
                    _handleSwap(users[msg.sender], tokenAmount, pool[i], _tokens_[i], WETH, uniV[i] == 3 ? true : false);
                for (uint256 j = 1; j <= users[msg.sender].round; j++) {
                    users[msg.sender].tokenBalances[_tokens_[i]][j] = 0;
                }
                users[msg.sender].theTokenBalance[_tokens_[i]] = 0;
                totalETH += uint256(ethAmountRecieved);
            }
            // for (uint256 j = 1; j <= users[msg.sender].round; j++) {
            //     users[msg.sender].tokenBalances[_tokens_[i]][j] -= tokenAmount;
            //     users[msg.sender].theTokenBalance[_tokens_[i]] -= tokenAmount;
            // }
        }
        // Fees memory theFee = feeData;
        // uint256 fee = calculateFee(totalETH, FeeDirection.Withdraw);
        uint256 netETH = getFee(totalETH, FeeDirection.Withdraw);
        // uint256 fee = (totalETH * theFee.WithdrawFee) / SFACTOR;
        require(netETH > 0, "NE"); // NE > Withdraw: No ETH

        IERC20(WETH).transfer(msg.sender, netETH);

        _updateAllUserBalances();
        // IERC20(WETH).transfer(admin, totalETH);
    }

    /// @notice Withdrawing ETH balances in the contract
    function withdrawETH() external onlyRole(ADMIN_ROLE) {
        uint256 cBalance = address(this).balance;
        // require(msg.sender == admin, "OA"); // OA > withdraw ETH: only admin
        payable(msg.sender).transfer(cBalance);
    }

    // todo: check if this is needed to be here
    /// @notice Updating the user's values
    /// @param _user user's address
    // function updateUserValues(address _user) external {
    //     (uint256[] memory values, /*uint256 totalValue*/ ) = _getPortfoTotalValue();
    //     UserData storage user = users[_user];

    //     // Calculate new value based on the current token values
    //     uint256 newValue = 0;
    //     for (uint256 i = 0; i < tokens.length; i++) {
    //         uint256 tokenAmount = user.theTokenBalance[tokens[i]];
    //         uint256 tokenValue = (values[i] * tokenAmount) / 100; // Assuming 2 decimal places
    //         newValue += tokenValue;
    //     }

    //     // Store initial value if not set
    //     // if (user.initialValue == 0) {
    //     //     user.initialValue = newValue;
    //     // }

    //     // Update new value
    //     user.value[1] = newValue;
    // }

    /* ================= public functions    ================= */

    /// @notice Main function. Starting the depositing process of the user and turning user's funds into tokens
    /// @param wethAmount eth amount depositing
    /// @param tokensData Token data of a user(including usdPrice, pool data, etc.)
    function deposit(uint256 wethAmount, bytes memory tokensData) public payable whenNotPaused {
        if (msg.value > 0) {
            // this.depositETH{value: msg.value}();
            WETH9.deposit{value: msg.value}();
            bool success = WETH9.transfer(address(this), msg.value);
            require(success, "ED"); // ED > Error depositing
        }
        require(WETH9.balanceOf(address(this)) >= wethAmount, "LD"); // LD > Lack of deposit amount
        // require(WETH9.balanceOf(msg.sender) > wethAmount, "Lack of deposit amount");
        // IERC20(WETH).transferFrom(msg.sender, address(this), wethAmount);
        require(msg.value == 0 || msg.value == wethAmount, "WA"); // WA > Wrong amount sent

        (address[] memory pool, address[] memory tokenOut, uint8[] memory uniV) = _getTokensData(tokensData);

        UserData storage user = users[msg.sender];
        // uint256 round = user.round;
        user.round++;
        uint256 totalValue = wethAmount;
        uint256 netValue = getFee(totalValue, FeeDirection.Deposit);
        user.balance[user.round] += netValue;
        user.wethValueFirst = totalValue;
        if (portfoValues[address(this)].initPrices[tokenOut[0]] == 0) {
            _addInitialValues(totalValue, tokensData);
        }
        // if (msg.sender == admin) {
        //     addInitialValues(getTokenPriceInUSD(WETH), tokensData);
        // }

        _processTokens(user, netValue, pool, WETH, tokenOut, uniV);
    }

    /// @notice Whitelisting a user
    /// @param _user Address of the user
    function addWhitelisted(address _user) external onlyRole(ADMIN_ROLE) {
        addUser(_user);
        _grantRole(WHITELISTED_ROLE, _user);
    }

    /// @notice Removing a user from Whitelist
    /// @param _user Address of the user
    function removeWhitelisted(address _user) public onlyRole(ADMIN_ROLE) {
        _revokeRole(WHITELISTED_ROLE, _user);
    }

    /// @notice If swapping of a token fails, it is possible to make the swap again
    /// @param _user user's address
    /// @param tokensData tokens data to try to swap again
    function swapUserQueueBuy(address _user, bytes memory tokensData) public onlyRole(ADMIN_ROLE) {
        address[] memory sQueue = new address[](users[_user].swapQueue.length);
        uint256 netValue = _userTokenBalance(_user, WETH) / sQueue.length;
        (address[] memory pool, address[] memory tokenOut, uint8[] memory uniV) = _getTokensData(tokensData);
        for (uint256 i; i < sQueue.length; i++) {
            _processTokens(users[_user], netValue, pool, WETH, tokenOut, uniV);
            users[_user].swapQueue.pop();
        }
    }

    /// @notice Getting the fees occuring during deposit/withdraw
    /// @param wethAmount incoming amount to deduct fee of
    /// @return final value remaining after deducting the fee
    function getFee(uint256 wethAmount, FeeDirection _direction) public payable returns (uint256) {
        uint256 totalValue;
        uint256 pmFee;
        totalValue = wethAmount;
        if (msg.sender == admin) pmFee = 0;
        pmFee = _calculateFee(totalValue, _direction);
        // ethBalances[admin] += pmFee;
        accumulatedETHFees += pmFee;
        // WETH9.transfer(admin, pmFee);
        emit FeeReceived(admin, pmFee);

        return totalValue - pmFee;
    }

    /// @notice total amount of all tokens of the user
    /// @param _user user's address
    /// @return tokens addresses
    /// @return tokens balances
    function userTokensBalance(address _user) public view returns (address[] memory, uint256[] memory) {
        address[] memory tokensInMemory = tokens;
        uint256[] memory tokensBalances = new uint256[](tokensInMemory.length);
        for (uint256 i; i < tokensInMemory.length; i++) {
            tokensBalances[i] = _userTokenBalance(_user, tokensInMemory[i]);
        }
        // emit UserTokensBalance(_user, tokensInMemory, tokensBalances);
        return (tokensInMemory, tokensBalances);
    }

    /// @notice At certain times, tokens of the total portfolio of the contract will be rebalanced using this function
    /// @param tokensData tokens data
    function doRebalance(bytes memory tokensData) public onlyRole(ADMIN_ROLE) {
        (address[] memory pool, /*address[] memory tokenOut*/, uint8[] memory uniV) = _getTokensData(tokensData);
        uint256 totalValue = 0;
        uint256[] memory values = new uint256[](tokens.length);
        // (values, totalValue) = getPortfoTotalValue(activePools[token].activeWethPool, activePools[token].activeUsdPool);

        for (uint256 i = 0; i < tokens.length; i++) {
            // uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            uint256 price = _getTokenPriceInUSD(tokens[i]);
            // uint256 price = getTokenPriceInUSD(tokens[i], pool[i]);
            values[i] = IERC20(tokens[i]).balanceOf(address(this)) * price;
            // values[i] = balance * price;
            unchecked {
                totalValue += values[i];
            }
        }

        uint256 targetValue = totalValue / tokens.length;
        address[] memory tOut = new address[](tokens.length);
        for (uint256 w; w < tOut.length; w++) {
            tOut[w] = WETH;
        }

        uint256 tmpRecoveryBalnace = address(this).balance;
        // address[] memory _tokens_ = tokens;
        // address[] memory userAdds = userAddresses;
        uint256[] memory amtToBuySell = new uint256[](tokens.length);
        // uint256[] memory amtToBuy = new uint256[](tokens.length);
        bool[] memory status = new bool[](tokens.length);

        // uint256 usersCount = userAdds.length;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (values[i] > targetValue) {
                // uint256 excessValue = values[i] - targetValue;
                uint256 amountToSell = (values[i] - targetValue) / _getTokenPriceInUSD(tokens[i]);
                // uint256 amountToSell = excessValue / getTokenPriceInUSD(tokens[i]);
                _processTokens(users[admin], amountToSell, pool, tokens[i], tOut, uniV);
                amtToBuySell[i] = amountToSell / userAddresses.length;
                status[i] = false; // sell
                    // _sellToken(tokens[i], amountToSell);
            } else {
                uint256 amountToBuy = (((targetValue - values[i]) / _getTokenPriceInUSD(tokens[i])) * SFACTOR)
                    * (_getTokenPriceInWETH(tokens[i], activePools[tokens[i]].activeWethPool) * SFACTOR);
                // uint256 amountToBuy = ((amount) * SFACTOR)
                //     * (getTokenPriceInWETH(tokens[i], activePools[tokens[i]].activeWethPool) * SFACTOR);
                if (recoveryBalance < amountToBuy) continue;

                _processTokensRebalance(users[admin], amountToBuy, pool[i], WETH, tokens[i], uniV[i]);
                amtToBuySell[i] = amountToBuy / userAddresses.length;
                status[i] = true; // sell
                tmpRecoveryBalnace = tmpRecoveryBalnace - address(this).balance;
                recoveryBalance -= tmpRecoveryBalnace;
            }
        }

        for (uint256 i; i < userAddresses.length; i++) {
            _updateUsersBalances(userAddresses[i], tokens, amtToBuySell, status);
        }

        emit Rebalanced(block.timestamp);
    }

    /// @notice withdrawing all the tokens in contract by admin
    function adminWithdrawWholeFundTokens() public onlyRole(ADMIN_ROLE) {
        bytes memory data = _calcTotalTokensAmount();
        (address[] memory _tokens_, uint256[] memory _balances_) = abi.decode(data, (address[], uint256[]));
        for (uint256 i; i < _tokens_.length; i++) {
            // IERC20 tokenContract = IERC20(_tokens_[i]);
            IERC20(_tokens_[i]).transfer(admin, _balances_[i]);
        }
    }

    /// @notice Can be called emergency exit. Swapping all the contract's funds into WETH and transfer them to the user with ADMIN_ROLE cdredentials
    /// @param tokensData tokens data
    function adminWithdrawWholeFundWETH(bytes memory tokensData) public onlyRole(ADMIN_ROLE) {
        // withdraw all tokens in contract
        // UserData storage user = users[admin];
        uint256 totalETH = 0;
        (address[] memory pool,, uint8[] memory uniV) = _getTokensData(tokensData);
        // emit LOG(pool, uniV);
        bytes memory data = _calcTotalTokensAmount();
        (address[] memory _tokens_, uint256[] memory _balances_) = abi.decode(data, (address[], uint256[]));
        for (uint256 i; i < _tokens_.length; i++) {
            uint256 tokenAmount = _balances_[i];
            // IERC20 tokenContract = IERC20(_tokens_[i]);
            if (tokenAmount > 0) {
                int256 ethAmountRecieved =
                    _handleSwap(users[admin], tokenAmount, pool[i], _tokens_[i], WETH, uniV[i] == 3 ? true : false);
                totalETH += uint256(ethAmountRecieved);
            }
        }
        require(totalETH > 0, "NE"); // NE > Withdraw: No ETH
        IERC20(WETH).transfer(admin, totalETH);
    }

    /// @notice Removing multiple tokens from the token's list
    /// @param _index the index of tokens
    function removeTokens(uint256[] memory _index) public onlyRole(ADMIN_ROLE) {
        for (uint256 i; i < _index.length; i++) {
            removeToken(_index[i]);
        }
    }

    /// @notice Pause or unpause
    /// @param _pState state of the contract(true: pause, false: unpause)
    function pauseOrUnpause(bool _pState) public onlyRole(ADMIN_ROLE) {
        if (_pState) _pause();
        else _unpause();
    }

    /// @notice Returning list of users
    /// @return List of user addresses defined in the contract
    function usersList() public view returns (address[] memory) {
        return userAddresses;
    }

    /// @notice Returning list of tokens
    /// @return List of token addresses defined in the contract
    function tokensList() public view returns (address[] memory) {
        return tokens;
    }

    /// @notice Checking the user's failed swaps tokens
    /// @param _user user's address
    function checkSwapQueue(address _user) public view returns (address[] memory) {
        return users[_user].swapQueue;
    }

    /// @notice Checking users which has failed swaps
    /// @return _user address of users
    /// @return _swpQueue address of tokens which has failed swap
    function checkUsersWithSwapQueue() public view returns (address[] memory _user, address[] memory _swpQueue) {
        UserData storage user;
        _user = new address[](userAddresses.length);
        _swpQueue = new address[](userAddresses.length);
        for (uint256 i; i < _user.length; i++) {
            user = users[userAddresses[i]];
            for (uint256 j; j < user.swapQueue.length; j++) {
                if (user.swapQueue[j] == address(0)) continue;
                else _swpQueue[j] = user.swapQueue[j];
            }
            _user[i] = userAddresses[i];
        }
    }

    /* ================= internal functions    ================= */

    /// @notice setting initial values in first time deposit occures
    /// @param _usd initial value in terms of USD
    /// @param tokensData tokens data
    function _addInitialValues(uint256 _usd, bytes memory tokensData) internal /*onlyRole(ADMIN_ROLE)*/ {
        portfoValues[address(this)].totalInitValue = _usd;
        (, address[] memory tokenOut,) = _getTokensData(tokensData);
        for (uint256 i; i < tokenOut.length; i++) {
            portfoValues[address(this)].initPrices[tokenOut[i]] = _getTokenPriceInUSD(tokenOut[i]);
        }
        // emit InitValuesSet(_usd, tokenOut, _tUsdt);
    }

    /// @notice Check if there is need for make rebalance
    /// @param tokensData token's data
    /// @return need if total percentage difference is more than 10, return true, else reutrn false
    function needToRebalance(bytes memory tokensData) external returns (bool need) {
        ( /*address[] memory pool*/ , address[] memory tokenOut,) = _getTokensData(tokensData);
        int256 percentages;
        for (uint256 i; i < tokenOut.length; i++) {
            uint256 initialPrice = portfoValues[address(this)].initPrices[tokenOut[i]];
            uint256 currentPrice = _getTokenPriceInUSD(tokenOut[i]);
            int256 priceDifference = (int256(currentPrice) * 10000) - (int256(initialPrice) * 10000);
            int256 percentageChange = (priceDifference * 100) / (int256(initialPrice) * 10000);
            if (percentageChange >= 0) {
                percentages += percentageChange;
            } else {
                percentages = percentageChange - percentages;
            }
            need = percentages >= 10 ? true : false;
        }
    }

    /// @notice Adding user (will be called whenever a user gets WHITELISTED_ROLE access level)
    /// @param userAddress user's address
    function addUser(address userAddress) internal {
        if (!isUserAdded[userAddress]) {
            userAddresses.push(userAddress);
            isUserAdded[userAddress] = true;
            // emit UserAdded(userAddress);
        }
    }

    /// @notice Calculating the fees occuring during deposit/withdraw
    /// @param _amount incoming amount to calculate fee of
    /// @param _direction direction of the fee(deposit:1 or withdraw:2)
    /// @return fee calculated fee amount
    function _calculateFee(uint256 _amount, FeeDirection _direction) internal view returns (uint256 fee) {
        Fees storage theFee = feeData;
        if (_direction == FeeDirection.Deposit) {
            fee = (_amount * theFee.depositFee) / SFACTOR;
        } else {
            fee = (_amount * theFee.WithdrawFee) / SFACTOR;
        }
        // fee = (_amount * feeAmount) / SFACTOR;
    }

    function _checkSlippage(uint256 amount) internal view returns (uint256 minAmount) {
        minAmount = (amount * (10000 - slippageTolerance)) / 10000;
    }

    function _getTokensData(bytes memory tokensData)
        internal
        returns (address[] memory path, address[] memory tokenOut, uint8[] memory uniV)
    {
        (path, uniV) = abi.decode(tokensData, (address[], uint8[]));
        // (path, tokenOut, uniV) = abi.decode(tokensData, (address[], address[], uint8[]));
        // require(path.length == tokenOut.length && tokenOut.length == uniV.length, "Array lengths mismatch");
        require(path.length == uniV.length, "ALM"); // ALM > Array lengths mismatch
        IUniswapV3Pool v3Pool;
        tokenOut = new address[](path.length - 1);
        for (uint256 i; i < path.length; i++) {
            v3Pool = IUniswapV3Pool(path[i]);
            address tInAdr;
            address tOutAdr;
            if (v3Pool.token0() == WETH) {
                tInAdr = v3Pool.token0();
                tOutAdr = v3Pool.token1();
            } else {
                tInAdr = v3Pool.token1();
                tOutAdr = v3Pool.token0();
            }
            // emit TokenData(path[i], tInAdr, tOutAdr, uniV[i]);
            if (tOutAdr != USDC) {
                tokenOut[i] = tOutAdr;
                activePools[tOutAdr].activeWethPool = path[i];
                activePools[tOutAdr].tokenIn = tInAdr;
                activePools[tOutAdr].tokenOut = tOutAdr;
                // activePools[tokenOut[i]].tokenOut = tokenOut[i];
                activePools[tOutAdr].uniV = uniV[i];
            }
            if (activePools[WETH].activeUsdPool == address(0) && tOutAdr == USDC) {
                activePools[WETH].activeUsdPool = path[i];
                activePools[WETH].uniV = uniV[i];
            }
        }
        // activePools[WETH].activeUsdPool = 0xA374094527e1673A86dE625aa59517c5dE346d32;
        // activePools[WETH].activeUsdPool = 0xA374094527e1673A86dE625aa59517c5dE346d32;
    }

    function _processTokens(
        UserData storage user,
        uint256 netValue,
        address[] memory pool,
        address tokenIn,
        address[] memory tokenOut,
        uint8[] memory uniV
    ) internal {
        for (uint256 i; i < tokenOut.length; i++) {
            bool isV3Eth = uniV[i] == 3 ? true : false;

            if (tokenOut[i] != WETH) {
                _handleWETHToTokenSwap(user, tokenIn, netValue / tokenOut.length, tokenOut[i], pool[i], isV3Eth);
            } else {
                _handleTokenToTokenSwap(user, tokenIn, tokenOut[i], pool[i], isV3Eth);
            }
        }
    }

    function _processTokensRebalance(
        UserData storage user,
        uint256 netValue,
        address pool,
        address tokenIn,
        address tokenOut,
        uint8 uniV
    ) internal {
        bool isV3Eth = uniV == 3 ? true : false;
        _handleTokenToTokenSwapRebalance(user, netValue, tokenIn, tokenOut, pool, isV3Eth);
    }

    function _handleWETHToTokenSwap(
        UserData storage user,
        address token,
        uint256 ethAmountPerToken,
        address tokenOut,
        address pool,
        bool isV3Eth
    ) internal {
        _handleSwap(user, ethAmountPerToken, pool, token, tokenOut, isV3Eth);
    }

    function _handleTokenToTokenSwap(UserData storage user, address token, address tokenOut, address pool, bool isV3Eth)
        internal
        returns (int256 amtOut)
    {
        uint256 tBalance = user.tokenBalances[token][user.round];
        uint256 tokenBalance = tBalance > _userTokenBalance(admin, token) ? tBalance : _userTokenBalance(admin, token);
        amtOut = _handleSwap(user, tokenBalance, pool, token, tokenOut, isV3Eth);
    }

    function _handleTokenToTokenSwapRebalance(
        UserData storage user,
        uint256 amtToBuy,
        address token,
        address tokenOut,
        address pool,
        bool isV3Eth
    ) internal returns (int256 amtOut) {
        amtOut = _handleSwap(user, amtToBuy, pool, token, tokenOut, isV3Eth);
    }

    function _getCurrentPrice(address pool, uint256 ethAmountPerToken) internal view returns (uint256 price) {
        IUniswapV3Pool uniswapV3Pool = IUniswapV3Pool(pool);
        (uint160 sqrtPriceX96,,,,,,) = uniswapV3Pool.slot0();
        uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        require(ethAmountPerToken < (1 << 192), "ETHL"); // ETHL > ethAmountPerToken is too large
        uint256 numerator = ethAmountPerToken * (1 << 96);
        price = numerator / (priceX96);
        // price = (ethAmountPerToken * (1 << 192)) / (priceX96);
    }

    function _getSqrtPriceLimit(uint256 price, uint256 tolerance) internal pure returns (uint160) {
        uint256 upperPrice = price * (100 + tolerance) / 100;
        uint256 lowerPrice = price * (100 - tolerance) / 100;
        uint160 upperSqrtPriceX96 = uint160(_sqrt(upperPrice) * 2 ** 96);
        uint160 lowerSqrtPriceX96 = uint160(_sqrt(lowerPrice) * 2 ** 96);
        return (upperSqrtPriceX96 + lowerSqrtPriceX96) / 2;
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function _handleSwap(
        UserData storage user,
        uint256 amount,
        address pool,
        address tokenIn,
        address tokenOut,
        bool isV3Eth
    ) internal returns (int256) {
        address[] memory pairAddress = new address[](2);
        pairAddress[0] = tokenIn;
        pairAddress[1] = tokenOut;

        uint256[] memory amtOut = new uint256[](2);
        uint256 minAmountOut;
        if (!isV3Eth) {
            amtOut = IUniswapV2Router02(UNISWAP_V2_ROUTER).getAmountsOut(amount, pairAddress);
            minAmountOut = amtOut[1] > 0 ? _checkSlippage(amtOut[1]) : 0;
        } else {
            // bytes memory encodedPath = abi.encodePacked(pairAddress[0], uint24(10000), pairAddress[1]);
            // amtOut[1] = quoter.quoteExactInput(encodedPath, amount);
            // amtOut[1] = quoter.quoteExactInputSingle(tokenIn, tokenOut, 3000, amount, 0);
            uint256 price = _getCurrentPrice(pool, amount);
            // emit PRICE(price);
            minAmountOut = _getSqrtPriceLimit(price, 10);
        }

        if (isV3Eth) {
            return _handleUniswapV3Swap(user, amount, pool, tokenIn, tokenOut, uint160(minAmountOut));
        } else {
            return _handleUniswapV2Swap(user, amount, tokenIn, tokenOut, minAmountOut);
        }
    }

    function _handleUniswapV3Swap(
        UserData storage user,
        uint256 ethAmountPerToken,
        address pool,
        address token,
        address tokenOut,
        uint160 minAmount
    ) internal returns (int256) {
        user.swapQueue.push(token);
        int256 tokenAmountRecieved;
        try UniswapSwapLibrary.SwapV3Params({
            tokenInAmount: ethAmountPerToken,
            poolAddress: pool,
            tokenIn: token,
            tokenOut: tokenOut,
            sqrtLimitX96: uint160(minAmount),
            minAmountOut: minAmount
        }).swapOnUniswapV3() returns (int256 amountOut) {
            tokenAmountRecieved = amountOut;
            if (user.initialUSDTPricesOne[tokenOut][user.round] == 0) {
                // user.initialUSDTPricesOne[tokenOut][user.round] = usdtValue;
                // user.initialUSDTPrices[tokenOut][user.round] = uint256(tokenAmountRecieved) * usdtValue;
                user.tokenBalances[tokenOut][user.round] = uint256(tokenAmountRecieved);
                user.theTokenBalance[tokenOut] += uint256(tokenAmountRecieved);
            }
            // if (user.initialUSDTPricesOne[token][user.round] == 0) {
            //     user.initialUSDTPricesOne[token][user.round] = usdtValue;
            //     user.initialUSDTPrices[token][user.round] = uint256(tokenAmountRecieved) * usdtValue;
            // }
            // if (user.initialUSDTPrices[token][user.round] == 0) {
            //     user.initialUSDTPrices[token][user.round] = uint256(tokenAmountRecieved) * usdtValue;
            // }
            emit SwapSuccessful(msg.sender, ethAmountPerToken, tokenAmountRecieved, _symbols(tokenOut), "V3");
            // emit UserTokenBalance(tokenOut, user.round, user.tokenBalances[tokenOut][user.round]);
            // user.tShare[tokenOut] = calcUserTokenShare()
        } catch Error(string memory reason) {
            emit SwapFailed(msg.sender, minAmount, _symbols(token), reason);
            // user.swapQueue.push(token);
        } catch {
            emit SwapFailed(msg.sender, minAmount, _symbols(token), "Swap failed");
            // user.swapQueue.push(token);
        }
        return tokenAmountRecieved;
    }

    function _handleUniswapV2Swap(
        UserData storage user,
        uint256 ethAmountPerToken,
        address token,
        address tokenOut,
        uint256 minAmount
    ) internal returns (int256) {
        user.swapQueue.push(token);
        int256 tokenAmountRecieved;
        try UniswapSwapLibrary.SwapParams({
            tokenInAmount: ethAmountPerToken,
            tokenIn: token,
            tokenOut: tokenOut,
            minAmountOut: minAmount
        }).swapOnUniswapV2() returns (uint256[] memory amountOut) {
            tokenAmountRecieved = int256(amountOut[1]);
            // require(int256(minAmount) >= tokenAmountRecieved, "Slippage too high");
            if (user.initialUSDTPricesOne[tokenOut][user.round] == 0) {
                // user.initialUSDTPricesOne[tokenOut][user.round] = usdtValue;
                // user.initialUSDTPrices[tokenOut][user.round] = uint256(tokenAmountRecieved) * usdtValue;
                user.tokenBalances[tokenOut][user.round] = uint256(tokenAmountRecieved);
                user.theTokenBalance[tokenOut] += uint256(tokenAmountRecieved);
            }
            // if (user.initialUSDTPrices[tokenOut][user.round] == 0) {
            //     user.initialUSDTPrices[tokenOut][user.round] = uint256(tokenAmountRecieved) * usdtValue;
            //     user.tokenBalances[tokenOut][user.round] = uint256(tokenAmountRecieved);
            // }
            emit SwapSuccessful(msg.sender, ethAmountPerToken, tokenAmountRecieved, _symbols(tokenOut), "V2");
            // emit SwapSuccessful(msg.sender, ethAmountPerToken, tokenAmountRecieved, /*_symbols(token),*/ "MKR", "V2");
            // emit UserTokenBalance(tokenOut, user.round, user.tokenBalances[tokenOut][user.round]);
            // emit UserTokenBalance(
            //     tokenOut, user.round, user.tokenBalances[0x6B175474E89094C44Da98b954EedeAC495271d0F][user.round]
            // );
            user.swapQueue.pop();
        } catch Error(string memory reason) {
            emit SwapFailed(msg.sender, minAmount, _symbols(token), reason);
            // user.swapQueue.push(token);
        } catch {
            emit SwapFailed(msg.sender, minAmount, _symbols(token), "Swap failed");
            // user.swapQueue.push(token);
        }
        return tokenAmountRecieved;
    }

    /// @notice Checking current price of the tokens based on the off-chain data
    /// @param _user user's address
    /// @param _token token's address
    /// @param _currentPrice price of a specific token
    function _checkUserTokenCurrentValue(address _user, address _token, /*uint256 _round,*/ uint256 _currentPrice)
        internal
        view
        returns (uint256 tokenBalancePriceUSDT)
    {
        // UserData storage user = users[_user];
        uint256 tokenBalance = _userTokenBalance(_user, _token);
        // uint256 tokenBalance = user.tokenBalances[_token][_round];
        if (tokenBalance > 0) {
            tokenBalancePriceUSDT = (tokenBalance * _currentPrice);
        }
    }

    // todo: check user's share of portfo(for each token)
    /// @notice calculating current share of tokens from the total portfo
    /// @param _user user's address
    /// @return _tokens address of tokens
    /// @return tokensShare share amount of the tokens
    // function calcCurrentTokensShareOfPortfo(address _user)
    //     public
    //     returns (address[] memory _tokens, uint256[] memory tokensShare)
    // {
    //     // PortfoValue storage portfo = portfoValues[address(this)];
    //     // uint256 tokenCount = tokens.length;
    //     (address[] memory theTokens, /*uint256[] memory tokensBalances*/ ) = userTokensBalance(admin);
    //     _tokens = new address[](theTokens.length);
    //     tokensShare = new uint256[](theTokens.length);
    //     for (uint256 i; i < theTokens.length; i++) {
    //         tokensShare[i] = calcCurrentTokenShareOfPortfoByToken(_user, theTokens[i]);
    //         _tokens[i] = theTokens[i];
    //         portfoValues[address(this)].tCurrentShares[theTokens[i]] = tokensShare[i];
    //     }
    // }

    /// @notice total amount of a specific token of the user
    /// @param _user address of the user
    /// @param _token address of the specific token
    /// @return userTBalance total token balance of the user
    function _userTokenBalance(address _user, address _token) internal view returns (uint256 userTBalance) {
        UserData storage user = users[_user];
        for (uint256 i = 1; i <= user.round; i++) {
            // if (_token == WETH) {
            if (_token == WETH && i != 2) {
                userTBalance += user.balance[i];
            } else {
                // userTBalance += user.tokenBalances[_token][i];
                userTBalance += user.theTokenBalance[_token];
            }
            // emit UserTokenBalanceRound(_user, _token, i, userTBalance);
        }
        // emit UserTokenBalance(_user, _token, userTBalance);
    }

    /// @notice calculating initial value of a token from the total portfo
    /// @param _token token's address
    /// @return tokenShare share amount of the token
    function _calcInitTokenShareOfPortfo(address _token) internal returns (uint256 tokenShare) {
        // PortfoValue storage portfo = portfoValues[address(this)];
        // uint256 tokenCount = tokens.length;
        uint256 perTokenUSD = portfoValues[address(this)].totalInitValue / tokens.length;
        tokenShare = ((perTokenUSD * SFACTOR) * 100) / (portfoValues[address(this)].totalInitValue * SFACTOR);
        portfoValues[address(this)].tInitShares[_token] = tokenShare;
    }

    /// @notice calculating initial value of a token from the total portfo
    /// @return _tokens address of tokens
    /// @return tokensShare share amount of tokens
    function _calcInitTokensShareOfPortfo() internal returns (address[] memory _tokens, uint256[] memory tokensShare) {
        // PortfoValue storage portfo = portfoValues[address(this)];
        address[] memory tokensInMemory = tokens;
        _tokens = new address[](tokensInMemory.length);
        tokensShare = new uint256[](tokensInMemory.length);
        // address token;
        for (uint256 i; i < tokensInMemory.length; i++) {
            // token = tokensInMemory[i];
            _tokens[i] = tokensInMemory[i];
            tokensShare[i] = _calcInitTokenShareOfPortfo(tokensInMemory[i]);
        }
    }

    /// @notice Calculating total initial portfo value of the user
    /// @param _user user's address
    /// @return totalValue total initial portfo value
    function _calcUserInitialPortfoValue(address _user) internal returns (uint256 totalValue) {
        uint256[] memory tokenBalances = new uint256[](tokens.length);
        // totalValue;
        for (uint256 i; i < tokens.length; i++) {
            // address token = tokens[i];
            tokenBalances[i] = _userTokenBalance(_user, tokens[i]);
            uint8 tokenDecimals = IERC20Metadata(tokens[i]).decimals();
            uint256 tokenPriceInUSD;
            // uint256 tCurrentValue = (tokenBalances[i] / (10 ** 18)) * _getTokenPriceInUSD(tokens[i]);
            //todo: calculate user's current token value, using a function to calc user token value
            if (tokenDecimals <= 18) {
                tokenPriceInUSD = _getTokenPriceInUSD(tokens[i]);
            }
            uint256 tCurrentValue = (tokenBalances[i] * tokenPriceInUSD) / (10 ** 18);
            // uint256 tCurrentValue = tokenBalances[i] * _getTokenPriceInUSD(tokens[i]);
            // else if (tokenDecimals > 18) {
            //     // tokenBalance = tokenBalance / (10 ** (18 - tokenDecimals));
            //     // tokenBalance = tokenBalance / (10 ** (tokenDecimals - 18));
            // }
            users[_user].tokenValue[0][tokens[i]] = tCurrentValue;
            totalValue += tCurrentValue;
            users[_user].value[0] = tCurrentValue;
        }
        // users[_user].value[0] = totalValue;
    }

    /// @notice Calculating total current portfo value of the user
    /// @param _user user's address
    /// @return totalValue total current portfo value
    function _calcUserCurrentPortfoValue(address _user) internal returns (uint256 totalValue) {
        uint256[] memory tokenBalances = new uint256[](tokens.length);
        address[] memory _tokens = new address[](tokens.length);
        // totalValue;
        (_tokens, tokenBalances) = userTokensBalance(_user);
        for (uint256 i; i < tokens.length; i++) {
            // tokenBalances[i] = _userTokenBalance(_user, tokens[i]);
            uint8 tokenDecimals = IERC20Metadata(_tokens[i]).decimals();
            uint256 tokenPriceInUSD;
            if (tokenDecimals <= 18) {
                tokenPriceInUSD = _getTokenPriceInUSD(_tokens[i]);
            }
            uint256 tCurrentValue = (tokenBalances[i] * tokenPriceInUSD) / (10 ** 18);
            // uint256 tCurrentValue = tokenBalances[i] * _getTokenPriceInUSD(tokens[i]);
            users[_user].tokenValue[1][_tokens[i]] = tCurrentValue;
            totalValue += tCurrentValue;
        }
        users[_user].value[1] = totalValue;
    }

    /// @notice Calculating the difference in the total value for each user
    /// @param _user user's address
    /// @return diffPercentage percentage change in the portfolio value of the user
    function _calcUserValueDifference(address _user) internal returns (uint256 diffPercentage) {
        uint256 initialUserTotalValue = users[_user].value[0];
        uint256 difference = _calcUserCurrentPortfoValue(_user) - initialUserTotalValue;
        diffPercentage = (difference * SFACTOR) / (initialUserTotalValue * 100);
    }

    /// @notice Current share of a user from a token out of the whole portfo
    /// @param _user user's address
    /// @param _token address of tokens
    /// @return tokenShare share amount of the token
    // function calcCurrentTokenShareOfPortfoByToken(address _user, address _token) public returns (uint256 tokenShare) {
    //     uint256 tokenBalance;
    //     tokenBalance = _userTokenBalance(_user, _token);
    //     uint256 tCurrentValue = tokenBalance * _getTokenPriceInUSD(_token);
    //     (, uint256 totalVal) = _getPortfoTotalValue();
    //     tokenShare = (tCurrentValue * SFACTOR) / (totalVal * 100);
    // }

    /// @notice Calculating all the users share of total portfolio
    /// @return _users address of users
    /// @return _userShareOfTotalPortfo share of each user
    // function calcUsersShareOfTotalPortfo()
    //     public
    //     returns (address[] memory _users, uint256[] memory _userShareOfTotalPortfo)
    // {
    //     address[] memory _users_ = userAddresses;
    //     _users = new address[](_users_.length);
    //     _userShareOfTotalPortfo = new uint256[](_users_.length);
    //     for (uint256 i; i < _users_.length; i++) {
    //         _users[i] = _users_[i];
    //         _calcUserInitialPortfoValue(_users[i]);
    //         _userShareOfTotalPortfo[i] = _calcUserShareOfTotalPortfo(_users_[i]);
    //         // emit UserShare(_userShareOfTotalPortfo[i]);
    //         // users[_users_[i]].tSharePortfo = userShareOfTotalPortfo;
    //     }
    // }

    /// @notice Calculate user token value in terms of usdc
    /// @param _user user's address
    /// @param _token token's address
    /// @return usdc price of token
    function getUserTokenTotalValueInUSDC(address _user, address _token) public view returns (uint256) {
        uint256 tokenDecimals = IERC20Metadata(_token).decimals();
        uint256 userTokenBalance = _userTokenBalance(_user, _token);
        uint256 normalizedUserBalance = userTokenBalance * (10 ** (18 - tokenDecimals));

        uint256 tokenPriceInUSDC = _getTokenPriceInUSD(_token);
        uint256 userTokenValueInUSDC = (normalizedUserBalance * tokenPriceInUSDC) / 1e18; // Normalize to 18 decimals

        // uint256 userTokenValueInUSDC = (userTokenBalance * tokenPriceInUSDC) / 1e18;
        return userTokenValueInUSDC;
    }

    /// @notice Calculate user total value in usdc
    /// @param _user user's address
    /// @return total usdc value of the user
    function calculateUserTotalValueInUSD(address _user) public view returns (uint256) {
        uint256 userTotalValueInUSD = 0;

        // for (uint256 i = 0; i < userAddresses.length; i++) {
        for (uint256 j; j < tokens.length; j++) {
            // address token = tokens[j];
            uint256 userTokenValueInUSDC = getUserTokenTotalValueInUSDC(_user, tokens[j]);

            userTotalValueInUSD += userTokenValueInUSDC;
        }
        // }

        return userTotalValueInUSD;
    }

    /**
     * get user token share
     */
    /// @notice Calculating user token share
    /// @param _user user's address
    /// @param _token token's address
    /// @return user's token share
    function getUserTokenShare(address _user, address _token) public view returns (uint256) {
        uint256 userBalance = _userTokenBalance(_user, _token);
        uint256 totalBalance = _calcTotalTokenAmount(_token);
        uint8 tokenDecimals = IERC20Metadata(_token).decimals();
        if (totalBalance == 0) {
            return 0;
        }
        uint256 normalizedUserBalance = userBalance * (10 ** (18 - tokenDecimals));
        uint256 normalizedTotalBalance = totalBalance * (10 ** (18 - tokenDecimals));

        return (normalizedUserBalance * 1e20) / normalizedTotalBalance;

        // return (userBalance * 1e18) / (totalBalance * 100); // return value in 18 decimal places
    }

    function getUserTokensShare(address _user)
        internal
        view
        returns (address[] memory _tokens, uint256[] memory tokenShare)
    {
        tokenShare = new uint256[](tokens.length);
        _tokens = new address[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            tokenShare[i] = getUserTokenShare(_user, tokens[i]);
            _tokens[i] = tokens[i];
        }
    }

    function getAllUsersTokensShare()
        internal
        view
        returns (address[] memory _user, address[] memory _tokens, uint256[] memory _tokenShare)
    {
        _user = new address[](userAddresses.length);
        _tokenShare = new uint256[](tokens.length);
        _tokens = new address[](tokens.length);
        for (uint256 i; i < userAddresses.length; i++) {
            for (uint256 j; j < tokens.length; j++) {
                _tokenShare[j] = getUserTokenShare(_user[i], tokens[j]);
                _tokens[j] = tokens[j];
            }
        }
    }

    function calculateTotalPortfolioValueInUSD() internal view returns (uint256) {
        uint256 totalPortfolioValueInUSD = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            uint8 tokenDecimals = IERC20Metadata(token).decimals();
            uint256 totalTokenBalance = _calcTotalTokenAmount(token);
            uint256 normalizedTotalBalance = totalTokenBalance * (10 ** (18 - tokenDecimals));

            uint256 tokenPriceInUSD = _getTokenPriceInUSD(token);
            uint256 totalTokenValueInUSD = (normalizedTotalBalance * tokenPriceInUSD) / 1e18; // Normalize to 18 decimals

            totalPortfolioValueInUSD += totalTokenValueInUSD;
        }

        return totalPortfolioValueInUSD;
    }

    /**
     * get user portfolio share
     */
    function getUserPortfolioShare(address user) external view returns (uint256) {
        uint256 userTotalValueInUSD = calculateUserTotalValueInUSD(user);
        uint256 totalPortfolioValueInUSD = calculateTotalPortfolioValueInUSD();

        if (totalPortfolioValueInUSD == 0) {
            return 0;
        }

        // Return the user's percentage share as a value between 0 and 1 (scaled to 18 decimals)
        return (userTotalValueInUSD * 1e18) / totalPortfolioValueInUSD;
    }
    /**
     */

    function _calcUserShareOfTotalPortfo(address _user) internal view returns (uint256 userShareOfTotalPortfo) {
        (, uint256 totalVal) = _getPortfoTotalValue();
        userShareOfTotalPortfo = (users[_user].value[0] * SFACTOR) / (totalVal * 100);
        // userShareOfTotalPortfo = (users[_user].value[0] * SFACTOR) / (_totalValue * 100);
    }

    function _updateUserShareOfTotalPortfo(address _user) internal {
        uint256 userShare = _calcUserShareOfTotalPortfo(_user);
        users[_user].tSharePortfo = userShare;
    }

    function _updateUsersShareOfTotalPortfo() internal {
        address[] memory _users_ = userAddresses;
        for (uint256 i; i < _users_.length; i++) {
            _updateUserShareOfTotalPortfo(_users_[i]);
        }
    }

    /// @notice Updating user's balances after rebalancing
    /// @param _tokens tokens addresses
    /// @param _tokens tokens new amounts
    /// @param status status of the udpate(true: sell | false buy)
    function _updateUsersBalances(
        address _user,
        address[] memory _tokens,
        uint256[] memory _amounts,
        bool[] memory status
    ) internal {
        for (uint256 i; i < _tokens.length; i++) {
            if (status[i] == false) {
                for (uint256 j = 1; j <= users[_user].round; j++) {
                    users[_user].tokenBalances[_tokens[i]][j] -= (_amounts[i] / users[_user].round);
                }
                users[_user].theTokenBalance[_tokens[i]] -= _amounts[i];
            } else {
                for (uint256 j = 1; j <= users[_user].round; j++) {
                    users[_user].tokenBalances[_tokens[i]][j] += (_amounts[i] / users[_user].round);
                }
                users[_user].theTokenBalance[_tokens[i]] += _amounts[i];
            }
        }
    }

    /// @notice Updating users balances after a user withdrawn funds
    function _updateAllUserBalances() internal view {
        // (uint256[] memory values, /*uint256 totalValue*/ ) = _getPortfoTotalValue();
        for (uint256 i = 0; i < userAddresses.length; i++) {
            address userAddress = userAddresses[i];
            UserData storage user = users[userAddress];

            // for (uint256 j = 0; j < tokens.length; j++) {
            //     address tokenAddress = tokens[j];
            //     user.theTokenBalance[tokenAddress] = 0;
            // }

            // Update user's total balance
            uint256 newUserTotalBalance = 0;
            for (uint256 j = 0; j < tokens.length; j++) {
                address tokenAddress = tokens[j];
                uint256 tokenBalance = user.theTokenBalance[tokenAddress];
                uint256 tokenPriceInUSD = _getTokenPriceInUSD(tokenAddress);
                newUserTotalBalance +=
                    (tokenBalance * tokenPriceInUSD) / (10 ** IERC20Metadata(tokenAddress).decimals());
            }
            // user.totalInvested = newUserTotalBalance;
        }
    }

    function _resetUserTokenBalance(address _user, address _token) internal {
        UserData storage user = users[_user];
        for (uint256 i; i < user.round; i++) {
            delete user.tokenBalances[_token][user.round];
        }
        delete user.theTokenBalance[_token];
    }

    function _resetUserTokensBalance(address _user) internal {
        UserData storage user = users[_user];
        address[] memory tokenInMemory = tokens;
        for (uint256 i; i < user.round; i++) {
            delete user.tokenBalances[tokenInMemory[i]][user.round];
            delete user.theTokenBalance[tokenInMemory[i]];
        }
    }

    /// @notice Calculating total initial portfo value of the contract
    /// @return values current value of tokens (price each 1 unit of token * token balance)
    /// @return totalValue total initial portfo value
    function _getPortfoTotalValue() internal view returns (uint256[] memory values, uint256 totalValue) {
        uint256[] memory tokenBalances = new uint256[](tokens.length);
        // totalValue;
        values = new uint256[](tokenBalances.length);
        for (uint256 i; i < tokens.length; i++) {
            uint256 totalTokenValue = _getPortfoTotalValue(tokens[i]);
            // address token = tokens[i];
            IERC20 tokenContract = IERC20(tokens[i]);
            tokenBalances[i] = tokenContract.balanceOf(address(this));
            uint256 tCurrentValue = totalTokenValue;
            // uint256 tCurrentValue = tokenBalances[i] * _getTokenPriceInUSD(tokens[i]);
            values[i] = tCurrentValue;
            totalValue += tCurrentValue;
        }
    }

    /// @notice Calculating total portfo value of a token in the contract
    /// @param _token token's address
    /// @return totalTokenValue total portfo value of a token
    function _getPortfoTotalValue(address _token) internal view returns (uint256 totalTokenValue) {
        uint256 tokenBalance;
        uint256 tokenPriceInUSD;

        // address token = tokens[i];
        IERC20 tokenContract = IERC20(_token);
        tokenBalance = tokenContract.balanceOf(address(this));

        tokenPriceInUSD = _getTokenPriceInUSD(_token);

        uint8 tokenDecimals = IERC20Metadata(_token).decimals();
        // uint256 normalizedTokenBalance;

        if (tokenDecimals <= 18) {
            tokenPriceInUSD = tokenPriceInUSD; /* * (10 ** (18 - tokenDecimals));*/
        } else if (tokenDecimals > 18) {
            tokenBalance = tokenBalance / (10 ** (18 - tokenDecimals));
            // tokenBalance = tokenBalance / (10 ** (tokenDecimals - 18));
        }

        uint256 tCurrentValue = (tokenBalance * tokenPriceInUSD) / (10 ** 18);
        // uint256 tCurrentValue = tokenBalance * _getTokenPriceInUSD(_token);
        totalTokenValue += tCurrentValue;
    }

    function _symbols(address _token) internal view returns (string memory symbol) {
        symbol = IERC20Metadata(_token).symbol();
    }

    /// @notice Removing a token from the token's list
    /// @param _index the index of
    function removeToken(uint256 _index) internal {
        // emit TokenRemoved(tokens[_index]);
        tokens.removeElement(_index);
    }

    /// @notice Returning token price in terms of USD (each 1 unit of token)
    /// @param token token's address
    /// @return price of 1 unit of token
    function _getTokenPriceInUSD(address token) internal view returns (uint256) {
        // Get the price of the token in WETH
        uint256 tokenPriceInWETH = _getTokenPriceInWETH(token, activePools[token].activeWethPool);

        // Get the price of WETH in USD
        uint256 WETHPriceInUSD = _getTokenPriceInWETH(WETH, activePools[WETH].activeUsdPool);

        // At this point, both tokenPriceInWETH and WETHPriceInUSD are normalized to 18 decimals.

        // Calculate the price of the token in USD
        uint256 tokenPriceInUSD = (tokenPriceInWETH * WETHPriceInUSD) / (10 ** 18);

        // The final tokenPriceInUSD should also be in 18 decimals
        return tokenPriceInUSD;
    }

    /// @notice Token price in terms of WETH (each 1 unit of token)
    /// @param token token's address
    /// @param poolAddress weth/token pool address to calc prices
    /// @return price of 1 unit of token
    function _getTokenPriceInWETH(address token, address poolAddress) internal view returns (uint256 price) {
        // uint256 price;
        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        uint8 wethDecimals = 18;
        // First check Uniswap V3 pool
        if (poolAddress != address(0)) {
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
            // uint256 price = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18 >> (96 * 2);
            uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
            if (pool.token0() == token) {
                price = (priceX96 * (10 ** wethDecimals)) / (1 << 192);
            } else {
                // price = (10 ** tokenDecimals) * (1 << 96) / sqrtPriceX96;
                // price = price * (1 << 96) / sqrtPriceX96;
                price = (10 ** tokenDecimals) * (1 << 192) / priceX96;
                // price = (1e18 * (1 << 192)) / (priceX96);
            }

            // uint256 numerator = 1e18 * (1 << 96);
            // price = numerator / (priceX96);
            // price = (1e18 * (1 << 192)) / (priceX96);
            // price = priceX96 / (1 << 192);
            // return price;
        } else {
            uint256 amountIn = 10 ** uint256(tokenDecimals);
            address[] memory path = new address[](2);
            path[0] = token;
            path[1] = WETH;
            uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(amountIn, path);
            price = amountsOut[1];
        }
        // Normalize the price to 18 decimals if necessary
        if (tokenDecimals < wethDecimals) {
            price = price * (10 ** (wethDecimals - tokenDecimals));
        } else if (tokenDecimals > wethDecimals) {
            price = price / (10 ** (tokenDecimals - wethDecimals));
        }

        // return price / (10 ** (tokenDecimals));
    }

    /// @notice calculating total amount of a specific token
    /// @param _token address of the specific token
    /// @return contract's token balance
    function _calcTotalTokenAmount(address _token) internal view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /// @notice calculating total amount of all the tokens in the contract
    /// @return data token's address and token's balance for all the tokens
    function _calcTotalTokensAmount() internal view returns (bytes memory data) {
        // address[] memory tokensInMemory = tokens;
        uint256[] memory tokenBalances = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            // address token = tokens[i];
            IERC20 tokenContract = IERC20(tokens[i]);
            tokenBalances[i] = tokenContract.balanceOf(address(this));
        }
        data = abi.encode(tokens, tokenBalances);
    }

    fallback() external payable {}

    receive() external payable {
        // emit FundsRecieved(msg.sender, msg.value);
    }

    /// @notice Calculating the user's token share of a specific token
    /// @param _user address of the user
    /// @param _token address of the specific token
    /// @return userTShare token's share of the user
    // function calcUserTokenShare(address _user, address _token) internal view returns (uint256 userTShare) {
    //     // share of the user from each token
    //     userTShare = (_userTokenBalance(_user, _token) * SFACTOR) / _calcTotalTokenAmount(_token);
    // }

    /// @notice Calculating tokens share of a user
    /// @param _user address of the user
    /// @return token addresses of the user
    // /// @return shares of the user from each token in his portfo
    // function calcUserTokensShare(address _user) public view returns (address[] memory, uint256[] memory) {
    //     address[] memory tokensInMemory = tokens;
    //     uint256[] memory tokensShares = new uint256[](tokensInMemory.length);
    //     for (uint256 i; i < tokensInMemory.length; i++) {
    //         address token = tokensInMemory[i];
    //         tokensShares[i] = calcUserTokenShare(_user, token);
    //     }
    //     return (tokensInMemory, tokensShares);
    // }
}

library ArrayElemenetRemover {
    function removeElement(address[] storage _array, uint256 _index) public {
        require(_array.length > _index, "IB"); // IB > Index out of bound
        for (uint256 i = _index; i < _array.length - 1; i++) {
            _array[i] = _array[i + 1];
        }
        _array.pop();
    }
}

// /// @notice Checking the price of 1 piece of each tokens of the user for the current round
// /// @param _user User address
// /// @return Price of 1 piece of each token in user's tokenBalances
// /// @return address of each token
// function _checkUserRoundTokensInitialValue(address _user) internal returns (uint256[] memory, address[] memory) {
//     UserData storage user = users[_user];
//     address[] memory tokensInMemory = tokens;
//     uint256[] memory roundPrices = new uint256[](tokensInMemory.length);
//     address[] memory roundTokens = new address[](tokensInMemory.length);
//     // emit UserRound(user.round);
//     for (uint256 i = 0; i < tokensInMemory.length; i++) {
//         address token = tokensInMemory[i];
//         roundPrices[i] = user.initialUSDTPricesOne[token][user.round];
//         // emit UserRound(user.initialUSDTPricesOne[token][user.round]);
//         roundTokens[i] = token;
//     }
//     return (roundPrices, roundTokens);
// }

// function _updateAllUserBalances1() internal {
//     (uint256[] memory values, uint256 totalValue) = _getPortfoTotalValue();
//     for (uint256 i = 0; i < tokens.length; i++) {
//         // address tokenAddress = address(tokens[i]);
//         uint256 tokenValue = values[i];

//         for (uint256 j; j < userAddresses.length; j++) {
//             // UserData storage user = users[userAddresses[j]];
//             uint256 totalTokenBalance = tokenValue * totalValue;
//             for (uint256 k = 1; k <= users[userAddresses[i]].round; k++) {
//                 users[userAddresses[j]].tokenBalances[tokens[i]][j] -= (
//                     users[userAddresses[j]].theTokenBalance[tokens[i]] * totalTokenBalance
//                         / users[userAddresses[j]].round
//                 );
//             }
//             users[userAddresses[j]].theTokenBalance[tokens[i]] =
//                 (users[userAddresses[j]].theTokenBalance[tokens[i]] * totalTokenBalance) / totalValue;
//         }
//     }
// }

/// @notice Calculating tokens share of a user
/// @param _user address of the user
/// @return token addresses of the user
/// @return shares of the user from each token in his portfo
// function _calcUserTokensShare(address _user) internal returns (address[] memory, uint256[] memory) {
//     address[] memory tokensInMemory = tokens;
//     uint256[] memory tokensShares = new uint256[](tokensInMemory.length);
//     for (uint256 i; i < tokensInMemory.length; i++) {
//         address token = tokensInMemory[i];
//         tokensShares[i] = calcUserTokenShare(_user, token);
//     }
//     return (tokensInMemory, tokensShares);
// }

// /// @notice updating all the users token's share of portfolio
// function _updateTokenShares() internal {
//     UserData storage user;
//     address[] memory tokensInMemory = tokens;
//     address[] memory usersInMemory = new address[](userAddresses.length);
//     for (uint256 i; i < usersInMemory.length; i++) {
//         user = users[usersInMemory[i]];
//         address token;
//         for (uint256 j; j < tokensInMemory.length; j++) {
//             token = tokensInMemory[j];
//             user.tShare[token] = _calcUserTokenShare(usersInMemory[i], token);
//         }
//     }

//     emit TokenSharesUpdated(true);
// }
