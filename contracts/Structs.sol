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
    Version version;
    uint24 feeTier;
}

struct FailedSwap {
    address user;
    IERC20 token;
    uint256 amount;
    Version version;
    uint24 feeTier;
}

struct Portfolio {
    string name;
    string symbol;
    uint256 fee;
    address[] tokens;
    address owner;
    address portfolioAddress;
}