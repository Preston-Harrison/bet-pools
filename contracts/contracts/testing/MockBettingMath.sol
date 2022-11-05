// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../BettingPool/BettingMath.sol";

contract MockBettingMath {
    function calculatePayout(
        uint256 amount,
        uint256 odds,
        uint256 maxPayout,
        uint256 sidePayout,
        uint256 freeLiquidity
    ) external pure returns (uint256) {
        return BettingMath.calculatePayout(
            amount,
            odds,
            maxPayout,
            sidePayout,
            freeLiquidity
        );
    }
}