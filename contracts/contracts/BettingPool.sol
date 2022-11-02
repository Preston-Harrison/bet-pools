// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LiquidityPool.sol";
import "./BetToken.sol";

struct Side {
    /// Total payouts on this side
    uint256 payout;
    /// whether or not this side exists
    bool exists;
}

struct Market {
    /// Mapping of side id to sides
    mapping(uint256 => Side) sides;
    /// The side with the largest payout's payout
    uint256 largestSidePayout;
    /// The winning side, or bytes32(0) if the winner has not been set.
    /// If this is set, _canWithdraw must be false
    uint256 winningSide;
    /// The timestamp (in seconds) that bets must be placed before
    uint256 bettingPeriodEnd;
    // set to true if this market exists
    bool exists;
}

contract BettingPool is Ownable, LiquidityPool, BetToken {
    using Address for address;
    using SafeERC20 for IERC20;

    /// Mapping of market Id to market
    mapping(bytes32 => Market) private _markets;

    event CreateMarket(
        bytes32 indexed market,
        uint256 sides,
        uint256 bettingPeriodEnd
    );
    event SetWinningSide(bytes32 indexed market, uint256 side);

    /// Throws if the side is invalid
    modifier onlyExistingSide(bytes32 marketId, uint256 side) {
        Market storage market = _markets[marketId];
        require(market.sides[side].exists, "Invalid side ID");
        _;
    }

    /// @param bettingToken The token to accept bets in
    constructor(address bettingToken) LiquidityPool(bettingToken) {
        require(bettingToken.isContract(), "Betting token is not a contract");
    }

    /// @param marketId The id of the market to create
    /// @param sides The array of side ids
    /// corresponds with the side id with the same index
    /// @param bettingPeriodEnd The end of the betting period
    function createMarket(
        bytes32 marketId,
        uint8 sides,
        uint256 bettingPeriodEnd
    ) external onlyOwner {
        Market storage market = _markets[marketId];
        require(marketId != bytes32(0), "Market ID cannot be zero");
        require(!market.exists, "Market already exists");
        require(sides >= 2, "Must have at least 2 sides");
        require(
            bettingPeriodEnd > block.timestamp,
            "Betting must end in the future"
        );

        market.bettingPeriodEnd = bettingPeriodEnd;
        market.exists = true;

        for (uint256 i = 1; i <= sides; i++) {
            market.sides[i].exists = true;
        }

        emit CreateMarket(marketId, sides, bettingPeriodEnd);
    }

    /// Returns whether a market is still open for betting.
    /// Reverts if the market does not exist
    function _isMarketOpen(bytes32 marketId) private view returns (bool) {
        require(_markets[marketId].exists, "Market non existant");
        if (_markets[marketId].bettingPeriodEnd > block.timestamp) return false;
        if (_markets[marketId].winningSide != 0) return false;
        return true;
    }

    /// Calculates the payout given an amount and odds
    function _calculatePayout(uint256 amount, uint256 odds)
        private
        pure
        returns (uint256)
    {
        return (amount * odds) / 1 ether;
    }

    /// Adjusts odds based on the amount, given odds, and free liquidity
    function _adjustOdds(uint256 amount, uint256 odds)
        private
        view
        returns (uint256)
    {
        uint256 free = getFreeBalance();
        return 1 ether + (free * odds) / (free + amount);
    }

    /// @param marketId the market to bet
    /// @param better the user making the bet
    /// @param side the side to bet on
    /// @param amount the amount being bet
    /// @param odds the odds for this bet
    function _createBet(
        bytes32 marketId,
        address better,
        uint256 side,
        uint256 amount,
        uint256 odds
    ) private {
        Market storage market = _markets[marketId];

        // adjust odds before moving on with calculations
        uint256 adjustedOdds = _adjustOdds(amount, odds);
        uint256 payout = _calculatePayout(amount, adjustedOdds);

        // if the market has become the new largest side payout, increase
        // the reserved amount so that the new reserved amount includes
        // the new total payout
        market.sides[side].payout += payout;
        if (market.sides[side].payout > market.largestSidePayout) {
            increaseReservedAmount(
                market.sides[side].payout - market.largestSidePayout
            );
            market.largestSidePayout = market.sides[side].payout;
        }

        // since market specific logic is taken care of, mint the token
        mintBet(better, marketId, payout, side);
    }

    /// Returns the side for a market
    function getSide(bytes32 marketId, uint256 side)
        external
        view
        returns (Side memory)
    {
        return _markets[marketId].sides[side];
    }

    /// Returns the market details
    function getMarket(bytes32 marketId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        Market storage market = _markets[marketId];
        return (
            market.largestSidePayout,
            market.winningSide,
            market.bettingPeriodEnd,
            market.exists
        );
    }

    /// Places a bet on a side, given a unique betKey (used for claiming / withdrawing).
    /// Note the amount of the bet is calculated using the _transferIn function.
    /// @param marketId The id of the market to bet on
    /// @param side The side to back
    /// @param better The better for whom to allocate the bet to
    function bet(
        bytes32 marketId,
        uint256 side,
        address better,
        uint256 odds // TODO signing
    ) external onlyExistingSide(marketId, side) {
        require(_isMarketOpen(marketId), "Market not open");

        uint256 amount = transferIn();
        require(amount > 0, "Bet cannot be zero");

        _createBet(marketId, better, side, amount, odds);
    }

    /// Claims a bet with id betId
    function claim(uint256 betId) external {
        Bet memory recordedBet = getBet(betId);
        Market storage market = _markets[recordedBet.market];
        require(!_isMarketOpen(recordedBet.market), "Market still open");
        require(market.winningSide != 0, "Winning side not set");
        require(recordedBet.side == market.winningSide, "Bet did not win");

        uint256 payout = recordedBet.payout;
        // payout the owner of the token
        transferOut(ownerOf(betId), payout);
        // now that the user has been payed out, burn the token
        burnBet(betId);
        // since the bet is being payed out, the reserved amounts can be decreased
        decreaseReservedAmount(payout);
    }

    /// Sets the winning side of this bet pool
    /// @param marketId The market to set the winning side for
    /// @param side The side that won
    function setWinningSide(bytes32 marketId, uint256 side)
        external
        onlyExistingSide(marketId, side)
        onlyOwner
    {
        Market storage market = _markets[marketId];
        require(market.winningSide == 0, "winning side already set");
        require(!_isMarketOpen(marketId), "Market still open");

        market.winningSide = side;
        emit SetWinningSide(marketId, side);
    }
}
