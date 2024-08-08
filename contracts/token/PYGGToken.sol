// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PYGGportfolioRebalancer is ERC20 {

    constructor(string memory _name, string memory _symbol)
    ERC20(_name, _symbol){}
}