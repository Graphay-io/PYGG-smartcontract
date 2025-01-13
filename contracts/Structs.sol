// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum Version {
    V2,
    V3
}

struct Basket {
    IERC20 token;
    uint256 targetPercentage;
}

struct Portfolio {
    string name;
    string symbol;
    address[] tokens;
    address owner;
    address portfolioAddress;
}

struct Direction{
    bytes path;
    Version version;
}

struct SwapPath {
    Direction[] directions;
    uint256 amountIn;
}