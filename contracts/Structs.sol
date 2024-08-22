// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct TokenInfo {
    IERC20 token;
    uint256 targetPercentage;
    string version;
    uint24 feeTier;
}

struct FailedSwap {
    address user;
    IERC20 token;
    uint256 amount;
    string version;
    uint24 feeTier;
}