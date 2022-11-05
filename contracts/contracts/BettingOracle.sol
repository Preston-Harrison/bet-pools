// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./BettingFactory.sol";

struct OracleMarket {
    /// Mapping of side to whether a side exists
    mapping(bytes32 => bool) sideExists;
    /// The winning side, or NO_WINNER if no winner has been set
    bytes32 winningSide;
    /// The timestamp when bets are no longer permitted
    uint256 bettingPeriodEnd;
    /// Whether or not the market is cancelled. If a market is cancelled,
    /// it means that users can withdraw their funds (minus fees)
    bool isCancelled;
    /// True if the market exists, false otherwise
    bool exists;
}

contract BettingOracle is Ownable {
    using Address for address;

    /// The id of a market with no winner
    bytes32 public constant NO_WINNER = bytes32(0);

    /// Mapping of market id to oracle market
    mapping(bytes32 => OracleMarket) private _markets;
    address private immutable _bettingFactory;

    event OpenMarket(
        bytes32 indexed marketId,
        bytes32[] sides,
        uint256 bettingPeriodEnd
    );
    event WinnerSet(bytes32 indexed marketId, bytes32 winner);
    event CancelMarket(bytes32 indexed marketId);

    modifier onlyBettingPool() {
        require(
            BettingFactory(_bettingFactory).isBettingPool(msg.sender),
            "Caller not betting pool"
        );
        _;
    }

    constructor(address bettingFactory) {
        require(bettingFactory.isContract(), "Betting factory not contract");
        _bettingFactory = bettingFactory;
    }

    /// Creates a new market
    function openMarket(
        bytes32 marketId,
        bytes32[] calldata sides,
        uint256 bettingPeriodEnd
    ) external onlyOwner {
        require(!_markets[marketId].exists, "Market already exists");
        require(sides.length >= 2, "Must have at least 2 sides");
        require(sides.length < 256, "Must have less than 256 sides");
        _markets[marketId].bettingPeriodEnd = bettingPeriodEnd;
        _markets[marketId].exists = true;

        for (uint256 i = 0; i < sides.length; i++) {
            require(sides[i] != NO_WINNER, "Invalid side");
            // ? this check might be unnecessary
            require(!_markets[marketId].sideExists[sides[i]], "Duplicate side");
            _markets[marketId].sideExists[sides[i]] = true;
        }
        emit OpenMarket(marketId, sides, bettingPeriodEnd);
    }

    /// Sets the winner of a market when betting is over
    function setMarketWinner(bytes32 marketId, bytes32 winner)
        external
        onlyOwner
    {
        _validateMarketIsOperational(marketId, winner);
        require(
            _markets[marketId].winningSide == NO_WINNER,
            "Winner already set"
        );
        require(_isBettingOver(marketId), "Betting period not over");
        _markets[marketId].winningSide = winner;
        emit WinnerSet(marketId, winner);
    }

    /// Cancels a market, allowing users to withdraw their funds safely
    function cancelMarket(bytes32 marketId) external onlyOwner {
        require(_markets[marketId].exists, "Market does not exist");
        require(
            _markets[marketId].winningSide == NO_WINNER,
            "Winner already set"
        );
        require(!_markets[marketId].isCancelled, "Market already cancelled");
        _markets[marketId].isCancelled = true;
        emit CancelMarket(marketId);
    }

    /// Returns the details of a market
    function getMarket(bytes32 marketId)
        external
        view
        onlyBettingPool
        returns (
            bytes32,
            uint256,
            bool,
            bool
        )
    {
        OracleMarket storage market = _markets[marketId];
        return (
            market.winningSide,
            market.bettingPeriodEnd,
            market.isCancelled,
            market.exists
        );
    }

    /// Throws if a bet cannot be placed for a given market and sideId
    function validateBet(bytes32 marketId, bytes32 sideId)
        external
        view
        onlyBettingPool
    {
        _validateMarketIsOperational(marketId, sideId);
        require(!_isBettingOver(marketId), "Betting is over");
    }

    /// Throws if a bet cannot be claimed for a given market and side Id
    function validateClaim(bytes32 marketId, bytes32 sideId)
        external
        view
        onlyBettingPool
    {
        _validateMarketIsOperational(marketId, sideId);
        require(_isBettingOver(marketId), "Betting is not over");

        OracleMarket storage market = _markets[marketId];
        require(market.winningSide != NO_WINNER, "Market winner not set");
        require(market.winningSide == sideId, "Side is not winner");
    }

    /// Throws if a bet cannot be withdrawn for a given market Id
    function validateWithdraw(bytes32 marketId) external view onlyBettingPool {
        require(_markets[marketId].isCancelled, "Market not cancelled");
    }

    /// Throws if a market & side either does not exist, or is cancelled
    function _validateMarketIsOperational(bytes32 marketId, bytes32 sideId)
        private
        view
    {
        require(_markets[marketId].exists, "Market does not exist");
        require(_markets[marketId].sideExists[sideId], "Side does not exist");
        require(!_markets[marketId].isCancelled, "Market is cancelled");
    }

    /// Returns whether a market betting period end has passed
    function _isBettingOver(bytes32 marketId) private view returns (bool) {
        return block.timestamp >= _markets[marketId].bettingPeriodEnd;
    }
}
