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

    /// @param marketId the market to bet
    /// @param side the side to bet on
    /// @param amount the amount being bet
    /// @param odds the odds for this bet
    /// @return id the token id of the bet
    function _createBet(
        bytes32 marketId,
        bytes32 side,
        uint256 amount,
        uint256 odds,
        uint256 minOdds
    ) private returns (uint256) {
        Market storage market = _markets[marketId];

        uint256 payout = BettingMath.calculatePayout(
            amount,
            odds,
            market.maxPayout,
            market.payouts[side],
            getFreeBalance()
        );

        uint256 realOdds = payout * BettingMath.PRECISION / amount;
        require(realOdds >= minOdds, "Min odds not met");

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
        return mintBet(msg.sender, marketId, amount, payout, side);
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
    function getSidePayout(bytes32 marketId, bytes32 side)
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
        returns (uint256, uint256, uint256)
    {
        Market storage market = _markets[marketId];
        return (market.size, market.reserve, market.maxPayout);
    }

    /// Places a bet on a side, given a unique betKey (used for claiming / withdrawing).
    /// Note the amount of the bet is calculated using the _transferIn function.
    /// @param marketId The id of the market to bet on
    /// @param side The side to back
    function bet(
        bytes32 marketId,
        bytes32 side,
        uint256 minOdds,
        uint256 odds,
        uint256 expiry,
        bytes calldata signature
    ) external returns (uint256) {
        _oracle.validateBet(marketId, side);
        _validateOdds(odds, marketId, side, expiry, signature);

        uint256 amount = transferIn();
        require(amount > 0, "Bet cannot be zero");

        uint256 betAmount = collectFees(amount, FeeType.Bet);
        return _createBet(marketId, side, betAmount, odds, minOdds);
    }

    /// Claims a bet with id betId and returns the payout from the claim
    /// This can be called by anyone, and will always transfer the payout
    /// to the owner of the bet
    /// @param betId the id of the bet to claim
    /// @return payout the payout of the bet, also the amount transferred out
    function claimBet(uint256 betId) external returns (uint256) {
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
        return payout;
    }

    /// If a market has been cancelled (e.g. a sports game is called off),
    /// all betters can claim the amount they bet back (except for fees).
    /// This can be called by anyone, and withdraws the amount back to the
    /// owner of the bet token
    /// @param betId the bet to withdraw
    /// @return size the size of the bet, also the amount transferred out
    function withdrawBet(uint256 betId) external returns (uint256) {
        Bet memory betToken = getBet(betId);
        _oracle.validateWithdraw(betToken.market);
        _collapseMarketReserve(betToken.market);
        
        uint256 size = betToken.size;
        transferOut(ownerOf(betId), size);
        decreaseReservedAmount(size);
        burnBet(betId);
        return size;
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

        // if the market is cancelled, then all sizes must be available to payout.
        if (isCancelled && reserve > market.size) {
            decreaseReservedAmount(reserve - market.size);
        } else if (reserve > market.payouts[winningSide]) {
            /// at this point market is not cancelled, so the contract must reserve the
            /// total payouts of the winning side
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
