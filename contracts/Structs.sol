// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum Version {
    V2,
    V3
}

struct TokenInfo {
    IERC20 token;
    uint256 targetPercentage;
}

struct FailedSwap {
    address user;
    IERC20 token;
    uint256 amount;
}

struct Portfolio {
    string name;
    string symbol;
    address[] tokens;
    address owner;
    address portfolioAddress;
}

struct SwapPath {
    bytes path;
    uint256 amountIn;
    Version version;
}