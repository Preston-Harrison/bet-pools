// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BettingFactory.sol";

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

contract BettingPool {
    using Address for address;
    using SafeERC20 for IERC20;

    /// The address of this contract
    address private immutable _self;
    /// The address of the deployer of this contract
    address public immutable bettingFactory;
    /// The address of the token that betters can bet with
    address private immutable _bettingToken;
    /// The timestamp (in seconds) that bets must be placed before
    uint256 public immutable bettingPeriodEnd;

    /// The previous token balance of this contract.
    /// Only valid while bets are able to be placed.
    uint256 private _prevBalance;
    /// Mapping of beyKeys to bets
    mapping(bytes32 => Bet) public bets;

    /// Mapping of side ids to side properties
    mapping(bytes32 => Side) public sides;
    /// Total sum of all side sizes
    uint256 private _totalSideSize;
    /// The winning side, or bytes32(0) if the winner has not been set.
    /// If this is set, _canWithdraw must be false
    bytes32 public winningSide;
    /// Whether or not users can withdraw their sizes. If this is true, _winningSide must
    /// be bytes32(0).
    bool public canWithdraw;

    event BetPlaced(
        bytes32 indexed betKey,
        address indexed better,
        uint256 amount,
        uint256 payout,
        bytes32 side
    );
    event PayoutClaimed(bytes32 indexed betKey);
    event SetWinningSide(bytes32 winningSide);
    event WithdrawalsEnabled();
    event BetWithdrawn(bytes32 indexed betKey);

    /// Throws if the msg.sender is not the factory of this contract
    modifier onlyFactory() {
        require(msg.sender == bettingFactory, "Msg.sender not factory");
        _;
    }

    /// Throws if the side is invalid
    modifier onlyValidSide(bytes32 side) {
        /// all sides must be initialised with a starting value, so if the value is
        /// zero, the side is invalid
        require(sides[side].size > 0, "Invalid side ID");
        _;
    }

    /// @param bettingToken The token to accept bets in
    /// @param sides_ The array of side ids
    /// @param initialSizes The array of initial sizes. Each element in this array
    /// corresponds with the side id with the same index
    /// @param bettingPeriodEnd_ The end of the betting period
    constructor(
        address bettingToken,
        bytes32[] memory sides_,
        uint256[] memory initialSizes,
        uint256 bettingPeriodEnd_
    ) {
        require(bettingToken.isContract(), "Betting token is not a contract");
        require(msg.sender.isContract(), "Msg.sender is not factory");
        require(sides_.length <= 255, "Must be less than 256 sides");
        require(sides_.length >= 2, "Must have at least 2 sides");
        require(
            initialSizes.length == sides_.length,
            "Array lengths must be the same"
        );
        require(
            bettingPeriodEnd_ > block.timestamp,
            "Betting must end in the future"
        );

        _bettingToken = bettingToken;
        bettingPeriodEnd = bettingPeriodEnd_;
        bettingFactory = msg.sender;
        _self = address(this);
        canWithdraw = false;

        for (uint256 i = 0; i < sides_.length; i++) {
            require(sides_[i] != bytes32(0), "Side ID cannot be zero");
            require(initialSizes[i] > 0, "Initial size cannot be zero");
            _increaseSide(sides_[i], initialSizes[i], 0);
        }
    }

    /// Transfers in an amount by checking the previous balance of the contract
    /// and comparing it to the current balance. The difference is the amount that
    /// has been transferred in.
    /// @return amount The amount that was transferred in
    function _transferIn() private returns (uint256 amount) {
        assert(block.timestamp < bettingPeriodEnd);
        assert(!canWithdraw && winningSide == bytes32(0));
        uint256 nextBalance = IERC20(_bettingToken).balanceOf(_self);
        amount = nextBalance - _prevBalance;
        _prevBalance = nextBalance;
    }

    /// Increases the size and/or payout of a side
    /// @param side The side to increase
    /// @param size The size to increase
    /// @param payout The payout to increase
    function _increaseSide(
        bytes32 side,
        uint256 size,
        uint256 payout
    ) private {
        sides[side].size += size;
        sides[side].payouts += payout;
        _totalSideSize += size;
    }

    /// Transfers out an amount of _bettingToken to a receiver
    /// @param amount The amount to transfer out
    /// @param receiver The receiver of the funds
    function _transferOut(uint256 amount, address receiver) private {
        assert(block.timestamp > bettingPeriodEnd);
        assert(canWithdraw || winningSide != bytes32(0));
        IERC20(_bettingToken).safeTransfer(receiver, amount);
    }

    /// Gets the payout that an amount would get if they picked a side and won
    /// @param amount The amount to bet
    /// @param side The side to back
    /// @return payout The potential payout of the side
    function _getPayout(uint256 amount, bytes32 side)
        private
        view
        returns (uint256)
    {
        uint256 size = sides[side].size + amount;
        return amount + (amount * (_totalSideSize - size)) / size;
    }

    /// Places a bet on a side, given a unique betKey (used for claiming / withdrawing).
    /// Note the amount of the bet is calculated using the _transferIn function.
    /// @param side The side to back
    /// @param betKey A unique key used to claim or withdraw the bet later
    /// @param better The better for whom to allocate the bet to
    function bet(
        bytes32 side,
        bytes32 betKey,
        address better
    ) external onlyValidSide(side) {
        require(block.timestamp < bettingPeriodEnd, "Betting period is over");
        require(bets[betKey].better == address(0), "Bet already exists");

        uint256 amount = _transferIn();
        require(amount > 0, "Bet cannot be zero");

        uint256 payout = _getPayout(amount, side);
        _increaseSide(side, amount, payout);

        bets[betKey] = Bet(better, amount, payout, side);
        emit BetPlaced(betKey, better, amount, payout, side);
    }

    /// Claims a bet using a betKey.
    /// Requires that:
    ///     - a winning side is set
    ///     - the better is the msg.sender
    ///     - the bet is on the winning side
    /// @param betKey The key of the bet to claim
    function claim(bytes32 betKey) external {
        require(winningSide != bytes32(0), "Winning side not set");
        require(bets[betKey].better == msg.sender, "Msg.sender is not better");
        require(
            bets[betKey].side == winningSide,
            "Bet is not on winning side"
        );
        assert(block.timestamp > bettingPeriodEnd);
        assert(!canWithdraw);

        _transferOut(bets[betKey].payout, msg.sender);
        emit PayoutClaimed(betKey);
        delete bets[betKey];
    }

    /// Sets the winning side of this bet pool
    /// @param side The side that won
    function setWinningSide(bytes32 side)
        external
        onlyFactory
        onlyValidSide(side)
    {
        require(!canWithdraw, "withdraws are enabled");
        require(winningSide == bytes32(0), "winning side already set");
        require(block.timestamp > bettingPeriodEnd, "Betting is not over");
        assert(side != bytes32(0));

        winningSide = side;
        emit SetWinningSide(winningSide);

        IERC20(_bettingToken).safeApprove(bettingFactory, type(uint256).max);
        BettingFactory(bettingFactory).setBettingPoolBalance(
            sides[side].payouts
        );
    }

    /// If a pool becomes invalid for whatever reason, all bets can be cancelled and
    /// the bets can be withdrawn. This means that the initial amount each better deposited
    /// can be returned, without a winner set.
    function allowWithdraws() external onlyFactory {
        require(!canWithdraw, "withdraws already allowed");
        require(winningSide == bytes32(0), "winning side already selected");
        canWithdraw = true;
        emit WithdrawalsEnabled();
    }

    /// Withdraws the amount deposited amount from betKey
    function withdraw(bytes32 betKey) external {
        require(canWithdraw, "cannot withdraw from pool");
        require(bets[betKey].better == msg.sender, "Msg.sender is not better");

        _transferOut(bets[betKey].payout, msg.sender);
        emit BetWithdrawn(betKey);
        delete bets[betKey];
    }
}
