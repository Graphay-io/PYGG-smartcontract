// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TokenInfo, Version } from "../Structs.sol";

library TokenLibrary {
    function initializeTokens(TokenInfo[] storage portfolio, address[] calldata _tokens, uint256[] calldata _targetPercentages) external {
        require(_tokens.length == _targetPercentages.length, "!Misslengths");
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_targetPercentages[i] <= 10000, "!percentage");
            totalPercentage += _targetPercentages[i];
            portfolio.push(TokenInfo({
                token: IERC20(_tokens[i]),
                targetPercentage: _targetPercentages[i]
            }));
        }
        require(totalPercentage == 10000, "!totalPercentage");
    }

    // function getPortfolio(TokenInfo[] storage portfolio) external view returns (TokenInfo[] memory) {
    //     return portfolio;
    // }
}