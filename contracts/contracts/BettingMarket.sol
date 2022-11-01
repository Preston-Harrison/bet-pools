// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

struct Bet {
    /// The user who will receive the payout of the bet
    address better;
    /// The token amount used to put on the bet
    uint256 amount;
    /// The total payout the better will get (inclusive of their original bet).
    /// E.g better deposits amount, and receives payout. They do NOT receive payout + amount;
    uint256 payout;
    /// The id of the side the better is backing.
    bytes32 side;
}

struct Side {
    /// the total bets placed on a side
    uint256 size;
    /// the total payouts that a side will payout if it wins
    uint256 payouts;
}

struct Market {
    /// Mapping of beyKeys to bets
    mapping(bytes32 => Bet) bets;
    /// Mapping of side ids to side properties
    mapping(bytes32 => Side) sides;
    /// Total sum of all side sizes
    uint256 totalSideSize;
    /// The winning side, or bytes32(0) if the winner has not been set.
    /// If this is set, _canWithdraw must be false
    bytes32 winningSide;
    /// Whether or not users can withdraw their sizes. If this is true, _winningSide must
    /// be bytes32(0).
    bool canWithdraw;
    /// The timestamp (in seconds) that bets must be placed before
    uint256 bettingPeriodEnd;
    // set to true if this market exists
    bool exists;
}

contract BettingMarket is Ownable {
    using Address for address;
    using SafeERC20 for IERC20;

    /// The address of this contract
    address private immutable _self;
    /// The address of the token that betters can bet with
    address private immutable _bettingToken;

    /// The previous token balance of this contract.
    /// Only valid while bets are able to be placed.
    uint256 private _prevBalance;

    /// Mapping of market Id to market
    mapping(bytes32 => Market) private _markets;

    event CreateMarket(
        bytes32 indexed market,
        bytes32[] sides,
        uint256[] inititalSizes,
        uint256 bettingPeriodEnd
    );
    event AllowWithdraw(bytes32 indexed market);
    event SetWinningSide(bytes32 indexed market, bytes32 side);
    event PlaceBet(
        bytes32 indexed market,
        address indexed better,
        bytes32 indexed side,
        bytes32 betKey,
        uint256 amount,
        uint256 payout
    );
    event ClaimBet(bytes32 indexed market, bytes32 betKey);
    event WithdrawBet(bytes32 indexed market, bytes32 betKey);

    /// Throws if the side is invalid
    modifier onlyValidSide(bytes32 marketId, bytes32 side) {
        Market storage market = _markets[marketId];
        /// all sides must be initialised with a starting value, so if the value is
        /// zero, the side is invalid
        require(market.exists, "Market does not exist");
        require(market.sides[side].size > 0, "Invalid side ID");
        _;
    }

    /// @param bettingToken The token to accept bets in
    constructor(address bettingToken) {
        require(bettingToken.isContract(), "Betting token is not a contract");
        _bettingToken = bettingToken;
        _self = address(this);
    }

    /// @param marketId The id of the market to create
    /// @param sides The array of side ids
    /// @param initialSizes The array of initial sizes. Each element in this array
    /// corresponds with the side id with the same index
    /// @param bettingPeriodEnd The end of the betting period
    function createMarket(
        bytes32 marketId,
        bytes32[] calldata sides,
        uint256[] calldata initialSizes,
        uint256 bettingPeriodEnd
    ) external onlyOwner {
        Market storage market = _markets[marketId];
        require(marketId != bytes32(0), "Market id cannot be zero");
        require(!market.exists, "Market already exists");
        require(sides.length <= 255, "Must be less than 256 sides");
        require(sides.length >= 2, "Must have at least 2 sides");
        require(
            initialSizes.length == sides.length,
            "Array lengths must be the same"
        );
        require(
            bettingPeriodEnd > block.timestamp,
            "Betting must end in the future"
        );

        market.bettingPeriodEnd = bettingPeriodEnd;
        market.exists = true;

        for (uint256 i = 0; i < sides.length; i++) {
            require(sides[i] != bytes32(0), "Side ID cannot be zero");
            require(initialSizes[i] > 0, "Initial size cannot be zero");

            _increaseSide(marketId, sides[i], initialSizes[i], 0);
        }
        
        emit CreateMarket(
            marketId,
            sides,
            initialSizes,
            bettingPeriodEnd
        );
    }

    /// Transfers in an amount by checking the previous balance of the contract
    /// and comparing it to the current balance. The difference is the amount that
    /// has been transferred in.
    /// @return amount The amount that was transferred in
    function _transferIn() private returns (uint256 amount) {
        uint256 nextBalance = IERC20(_bettingToken).balanceOf(_self);
        amount = nextBalance - _prevBalance;
        _prevBalance = nextBalance;
    }

    /// Increases the size and/or payout of a side
    /// @param marketId the market of the side to increase
    /// @param side The side to increase
    /// @param size The size to increase
    /// @param payout The payout to increase
    function _increaseSide(
        bytes32 marketId,
        bytes32 side,
        uint256 size,
        uint256 payout
    ) private {
        Market storage market = _markets[marketId];
        market.sides[side].size += size;
        market.sides[side].payouts += payout;
        market.totalSideSize += size;
    }

    /// Transfers out an amount of _bettingToken to a receiver
    /// @param amount The amount to transfer out
    /// @param receiver The receiver of the funds
    function _transferOut(uint256 amount, address receiver) private {
        IERC20(_bettingToken).safeTransfer(receiver, amount);
        _prevBalance = IERC20(_bettingToken).balanceOf(_self);
    }

    /// Gets the payout that an amount would get if they picked a side and won
    /// @param amount The amount to bet
    /// @param marketId The id of the market to calculate for
    /// @param side The side to back
    /// @return payout The potential payout of the side
    function _getPayout(
        uint256 amount,
        bytes32 marketId,
        bytes32 side
    ) private view returns (uint256) {
        Market storage market = _markets[marketId];
        uint256 size = market.sides[side].size;

        // meant to represent amount + amount * (total size - side size) / (side size + amount)
        return
            amount +
            (amount * market.totalSideSize - amount * size) /
            (size + amount);
    }

    function getBet(bytes32 marketId, bytes32 betKey)
        external
        view
        returns (Bet memory)
    {
        return _markets[marketId].bets[betKey];
    }

    function getSide(bytes32 marketId, bytes32 side)
        external
        view
        returns (Side memory)
    {
        return _markets[marketId].sides[side];
    }

    function getMarket(bytes32 marketId)
        external
        view
        returns (
            uint256,
            bytes32,
            bool,
            uint256,
            bool
        )
    {
        Market storage market = _markets[marketId];
        return (
            market.totalSideSize,
            market.winningSide,
            market.canWithdraw,
            market.bettingPeriodEnd,
            market.exists
        );
    }

    /// Places a bet on a side, given a unique betKey (used for claiming / withdrawing).
    /// Note the amount of the bet is calculated using the _transferIn function.
    /// @param marketId The id of the market to bet on
    /// @param side The side to back
    /// @param betKey A unique key used to claim or withdraw the bet later
    /// @param better The better for whom to allocate the bet to
    function bet(
        bytes32 marketId,
        bytes32 side,
        bytes32 betKey,
        address better
    ) external onlyValidSide(marketId, side) {
        Market storage market = _markets[marketId];
        require(
            block.timestamp < market.bettingPeriodEnd,
            "Betting period is over"
        );
        require(market.bets[betKey].better == address(0), "Bet already exists");

        uint256 amount = _transferIn();
        require(amount > 0, "Bet cannot be zero");

        uint256 payout = _getPayout(amount, marketId, side);
        _increaseSide(marketId, side, amount, payout);

        market.bets[betKey] = Bet(better, amount, payout, side);
        emit PlaceBet(marketId, better, side, betKey, amount, payout);
    }

    /// Claims a bet using a betKey.
    /// Requires that:
    ///     - a winning side is set
    ///     - the better is the msg.sender
    ///     - the bet is on the winning side
    /// @param marketId The market from which to claim
    /// @param betKey The key of the bet to claim
    function claim(bytes32 marketId, bytes32 betKey) external {
        Market storage market = _markets[marketId];
        require(market.winningSide != bytes32(0), "Winning side not set");
        require(
            market.bets[betKey].better == msg.sender,
            "Msg.sender is not better"
        );
        require(
            market.bets[betKey].side == market.winningSide,
            "Bet is not on winning side"
        );
        assert(block.timestamp > market.bettingPeriodEnd);
        assert(!market.canWithdraw);

        _transferOut(market.bets[betKey].payout, msg.sender);
        emit ClaimBet(marketId, betKey);
        delete market.bets[betKey];
    }

    /// Sets the winning side of this bet pool
    /// @param marketId The market to set the winning side for
    /// @param side The side that won
    function setWinningSide(bytes32 marketId, bytes32 side)
        external
        onlyValidSide(marketId, side)
        onlyOwner
    {
        Market storage market = _markets[marketId];
        require(!market.canWithdraw, "withdraws are enabled");
        require(market.winningSide == bytes32(0), "winning side already set");
        require(
            block.timestamp > market.bettingPeriodEnd,
            "Betting is not over"
        );
        assert(side != bytes32(0));

        market.winningSide = side;
        emit SetWinningSide(marketId, side);
    }

    /// If a pool becomes invalid for whatever reason, all bets can be cancelled and
    /// the bets can be withdrawn. This means that the initial amount each better deposited
    /// can be returned, without a winner set.
    /// @param marketId The market to allow withdrawls for
    function allowWithdraws(bytes32 marketId) external onlyOwner {
        Market storage market = _markets[marketId];
        require(!market.canWithdraw, "withdraws already allowed");
        require(
            market.winningSide == bytes32(0),
            "winning side already selected"
        );
        market.canWithdraw = true;
        emit AllowWithdraw(marketId);
    }

    /// Withdraws the amount deposited amount from betKey
    /// @param marketId The market to withdraw from
    /// @param betKey The bet to withdraw
    function withdraw(bytes32 marketId, bytes32 betKey) external {
        Market storage market = _markets[marketId];
        require(market.canWithdraw, "cannot withdraw from pool");
        require(
            market.bets[betKey].better == msg.sender,
            "Msg.sender is not better"
        );

        _transferOut(market.bets[betKey].payout, msg.sender);
        emit WithdrawBet(marketId, betKey);
        delete market.bets[betKey];
    }
}
