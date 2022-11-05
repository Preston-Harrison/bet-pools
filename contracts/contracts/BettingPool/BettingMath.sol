// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

library BettingMath {
    // TODO maybe use fast inverse sqrt algorithm to save gas
    
    uint256 private constant PRECISION = 1 ether;
    uint256 private constant SQUARED_PRECISION = PRECISION**2;

    /// Adjusts payout based on the amount, given odds, and free liquidity
    function calculatePayout(
        uint256 amount,
        uint256 odds,
        uint256 maxPayout,
        uint256 sidePayout,
        uint256 freeLiquidity
    ) internal pure returns (uint256) {
        uint256 potentialPayout = (amount * odds) / 1 ether;
        if (maxPayout >= sidePayout + potentialPayout) {
            // potential payout + side payout is still less than max payout, so
            // linear odds can be used
            return odds;
        }
        // at this point, either the max payout equals the side payout, or the
        // side payout + potential payout makes the side payout greater than
        // the max payout. In either case, some sort of squashing needs to
        // occur to limit the payout to, at most, the free liquidity.
        // See https://www.desmos.com/calculator/0bqoalkv5n

        // value that will be scaled according to free liquidity
        uint256 scaledX = sidePayout + potentialPayout - maxPayout;
        // value that will be linearly scaled
        uint256 linearX = maxPayout - sidePayout;

        uint256 linearY = (linearX * odds) / 1 ether;
        
        // liquidity - liquidity / sqrt((2x / liquidity) + 1)
        uint256 scaledY = freeLiquidity -
            (freeLiquidity * PRECISION) /
            sqrt(2 * scaledX * SQUARED_PRECISION + SQUARED_PRECISION);

        return linearY + scaledY;
    }

    /// Stolen from https://github.com/paulrberg/prb-math/blob/main/contracts/PRBMath.sol#L599-L647
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) {
            return 0;
        }

        // Set the initial guess to the least power of two that is greater than or equal to sqrt(x).
        uint256 xAux = uint256(x);
        result = 1;
        if (xAux >= 0x100000000000000000000000000000000) {
            xAux >>= 128;
            result <<= 64;
        }
        if (xAux >= 0x10000000000000000) {
            xAux >>= 64;
            result <<= 32;
        }
        if (xAux >= 0x100000000) {
            xAux >>= 32;
            result <<= 16;
        }
        if (xAux >= 0x10000) {
            xAux >>= 16;
            result <<= 8;
        }
        if (xAux >= 0x100) {
            xAux >>= 8;
            result <<= 4;
        }
        if (xAux >= 0x10) {
            xAux >>= 4;
            result <<= 2;
        }
        if (xAux >= 0x4) {
            result <<= 1;
        }

        // The operations can never overflow because the result is max 2^127 when it enters this block.
        unchecked {
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1; // Seven iterations should be enough
            uint256 roundedDownResult = x / result;
            return result >= roundedDownResult ? roundedDownResult : result;
        }
    }
}