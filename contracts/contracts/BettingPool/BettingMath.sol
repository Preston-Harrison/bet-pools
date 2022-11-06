// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/math/Math.sol";

library BettingMath {
    // TODO maybe use fast inverse sqrt algorithm to save gas

    uint256 internal constant PRECISION = 1 ether;
    uint256 private constant SQRT_PRECISION = 1e9;

    /// Adjusts payout based on the amount, given odds, and free liquidity
    function calculatePayout(
        uint256 amount,
        uint256 odds,
        uint256 maxPayout,
        uint256 sidePayout,
        uint256 freeLiquidity
    ) internal pure returns (uint256) {
        uint256 potentialPayout = (amount * odds) / PRECISION;
        if (maxPayout >= sidePayout + potentialPayout) {
            // potential payout + side payout is still less than max payout, so
            // linear odds can be used
            return potentialPayout;
        }
        // at this point, either the max payout equals the side payout, or the
        // side payout + potential payout makes the side payout greater than
        // the max payout. In either case, some sort of squashing needs to
        // occur to limit the payout to, at most, the free liquidity.
        // See https://www.desmos.com/calculator/0bqoalkv5n

        // payout that is scaled linearly
        uint256 linearPayout = maxPayout - sidePayout;
        // payout that will be scaled
        uint256 scaledX = potentialPayout - linearPayout;

        // scaledY = squashing function applied to scaledX
        uint256 scaledY = freeLiquidity -
            (freeLiquidity * SQRT_PRECISION) /
            Math.sqrt(
                2 * scaledX * PRECISION / freeLiquidity + PRECISION,
                // Uses rounding up to keep the scaled Y to a minumum 
                // (since it is on the denominator)
                Math.Rounding.Up
            );

        return linearPayout + scaledY;
    }
}
