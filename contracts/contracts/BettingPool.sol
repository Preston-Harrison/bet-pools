// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./BettingMarket.sol";
import "./LiquidityPool.sol";

contract BettingPool is Ownable, LiquidityPool, BettingMarket {
    /// @param bettingToken The token users can use to bet
    constructor(address bettingToken)
        LiquidityPool(bettingToken)
        BettingMarket(bettingToken)
    {}
}
