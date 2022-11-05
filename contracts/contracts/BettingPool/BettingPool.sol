// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./LiquidityPool.sol";
import "./BetToken.sol";
import "../BettingOracle.sol";
import "./Transferrer.sol";
import "./FeeDistribution.sol";
import "./BettingMath.sol";

struct Market {
    /// Mapping of side id to total payout on each side
    mapping(bytes32 => uint256) payouts;
    /// The total value of bets on this market, in bettingToken
    uint256 size;
    /// The side with the maximum payout's payout
    uint256 maxPayout;
    /// The amount of bettingToken this market should reserve.
    /// While betting is active, this is either size, or the payout,
    /// of the side with the greatest payout, whichever is greater.
    /// If the market is cancelled, the market should reserve the size
    /// of everyones bets.
    /// If the market finishes successfully (i.e. betters can claim),
    /// the market should reserve the payout of the winning size.
    uint256 reserve;
}

contract BettingPool is LiquidityPool, BetToken {
    using Address for address;
    using SafeERC20 for IERC20;

    /// The oracle that provides betting information
    BettingOracle private immutable _oracle;

    /// Mapping of market Id to market
    mapping(bytes32 => Market) private _markets;

    /// @param bettingToken The token to accept bets in
    constructor(
        address bettingToken,
        address oracle,
        address owner
    ) Roles(owner) Transferrer(bettingToken) FeeDistribution(owner) {
        require(bettingToken.isContract(), "Betting token is not a contract");
        require(oracle.isContract(), "Oracle is not contract");
        _oracle = BettingOracle(oracle);
    }

    /// Returns the real (possible squashed) odds of a bet by taking the
    /// ratio of calculated payout to input amount. This can be used by
    /// routers to check the 'slippage' of odds.
    /// @param amount the bet amount
    /// @param odds the odds offered by the signer
    /// @param marketId the market in which this bet will be placed
    /// @param side the side on which this bet should be placed
    function getRealOdds(
        uint256 amount,
        uint256 odds,
        bytes32 marketId,
        bytes32 side
    ) external view returns (uint256) {
        Market storage market = _markets[marketId];
        uint256 payout = BettingMath.calculatePayout(
            amount,
            odds,
            market.maxPayout,
            market.payouts[side],
            getFreeBalance()
        );
        return payout * BettingMath.PRECISION / amount;
    }

    /// @param marketId the market to bet
    /// @param better the user making the bet
    /// @param side the side to bet on
    /// @param amount the amount being bet
    /// @param odds the odds for this bet
    function _createBet(
        bytes32 marketId,
        address better,
        bytes32 side,
        uint256 amount,
        uint256 odds
    ) private {
        Market storage market = _markets[marketId];

        uint256 payout = BettingMath.calculatePayout(
            amount,
            odds,
            market.maxPayout,
            market.payouts[side],
            getFreeBalance()
        );

        // adjust market values
        market.payouts[side] += payout;
        market.size += amount;

        // adjust the reserve of the market if either the size or payouts have
        // surpassed the current reserve
        uint256 newPayout = market.payouts[side];
        uint256 newSize = market.size;
        uint256 possibleGreaterReserve = Math.max(newPayout, newSize);
        if (possibleGreaterReserve > market.reserve) {
            increaseReservedAmount(possibleGreaterReserve - market.reserve);
            market.reserve = possibleGreaterReserve;
        }

        if (newPayout > market.maxPayout) {
            market.maxPayout = newPayout;
        }

        // since market specific logic is taken care of, mint the token
        mintBet(better, marketId, amount, payout, side);
    }

    /// Throws if the parameters provided are not signed by someone with SIGNER_ROLE
    function _validateOdds(
        uint256 odds,
        bytes32 market,
        bytes32 side,
        uint256 expiry,
        bytes calldata signature
    ) private view {
        require(odds > BettingMath.PRECISION, "Cannot have odds <= 1x");
        bytes memory message = abi.encodePacked(odds, market, side, expiry);
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(message));
        require(
            hasRole(SIGNER_ROLE, ECDSA.recover(hash, signature)),
            "Invalid signature"
        );
    }

    /// Returns the side for a market
    function getPayout(bytes32 marketId, bytes32 side)
        external
        view
        returns (uint256)
    {
        return _markets[marketId].payouts[side];
    }

    /// Returns the market details
    function getMarket(bytes32 marketId)
        external
        view
        returns (uint256, uint256)
    {
        return (_markets[marketId].size, _markets[marketId].reserve);
    }

    /// Places a bet on a side, given a unique betKey (used for claiming / withdrawing).
    /// Note the amount of the bet is calculated using the _transferIn function.
    /// @param marketId The id of the market to bet on
    /// @param side The side to back
    /// @param better The better for whom to allocate the bet to
    function bet(
        bytes32 marketId,
        bytes32 side,
        address better,
        uint256 odds,
        uint256 expiry,
        bytes calldata signature
    ) external {
        _oracle.validateBet(marketId, side);
        _validateOdds(odds, marketId, side, expiry, signature);

        uint256 amount = transferIn();
        require(amount > 0, "Bet cannot be zero");

        uint256 betAmount = collectFees(amount, FeeType.Bet);
        _createBet(marketId, better, side, betAmount, odds);
    }

    /// Claims a bet with id betId
    function claim(uint256 betId) external {
        Bet memory betToken = getBet(betId);
        _oracle.validateClaim(betToken.market, betToken.side);
        // since the oracle has validated the claim, collapse the market reserve
        _collapseMarketReserve(betToken.market);

        uint256 payout = betToken.payout;
        // payout the owner of the token
        transferOut(ownerOf(betId), payout);
        // now that the user has been payed out, burn the token
        burnBet(betId);
        // since the bet is being payed out, the reserved amounts can be decreased
        decreaseReservedAmount(payout);
    }

    /// This should only be called after a market has finished accepting bets, either
    /// by having a winning side set, or the market being closed for withdraws.
    /// This decreases the reserved amounts by the difference between the maximum
    /// possible reserved amount (where the winning side is not known, and the market has
    /// the possibility of cancellation) and the true reserved amount (the payout
    /// of the winning side if the market is not cancelled, or the size of all bets if the
    /// market is cancelled)
    function _collapseMarketReserve(bytes32 marketId) private {
        Market storage market = _markets[marketId];
        uint256 reserve = market.reserve;
        if (reserve == 0) {
            // the reserved amount has already been collapsed.
            return;
        }
        // either the market is cancelled, or the winning side is set
        (bytes32 winningSide, , bool isCancelled, ) = _oracle.getMarket(
            marketId
        );

        if (isCancelled && reserve > market.size) {
            decreaseReservedAmount(reserve - market.size);
        } else if (reserve > market.payouts[winningSide]) {
            /// at this point market is not cancelled, so winning side must be set
            decreaseReservedAmount(reserve - market.payouts[winningSide]);
        }
        market.reserve = 0;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return
            interfaceId == type(IAccessControl).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
