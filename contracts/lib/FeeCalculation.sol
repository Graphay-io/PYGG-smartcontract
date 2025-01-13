// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library FeeCalculation {

    function calculateAmount(uint256 amount, uint16 feePercentage) internal pure returns (uint256) {
        return (amount * feePercentage) / 10000;
    }

    function calculateAmountAfterFee(uint256 amount, uint16 feePercentage) internal pure returns (uint256, uint256) {
        uint256 fee = calculateAmount(amount, feePercentage);
        uint256 amountAfterFee = amount - fee;
        return (amountAfterFee, fee);
    }

    function calculatePercentage(uint256 amount, uint256 totalAmount) internal pure returns (uint256) {
        return (amount * 10000) / totalAmount;
    }
    

}