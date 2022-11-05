// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";

struct OracleMarket {
    mapping(bytes32 => bool) sideExists;
    bytes32 winningSide;
    uint256 bettingPeriodEnd;
    bool isCancelled;
    bool exists;
}

contract BettingOracle is Ownable {
    bytes32 public constant NO_WINNER = bytes32(0);

    mapping(bytes32 => OracleMarket) private _markets;

    event OpenMarket(bytes32 indexed marketId, bytes32[] sides, uint256 bettingPeriodEnd);
    event WinnerSet(bytes32 indexed marketId, bytes32 winner);

    function openMarket(
        bytes32 marketId,
        bytes32[] calldata sides,
        uint256 bettingPeriodEnd
    ) external onlyOwner {
        require(!_markets[marketId].exists, "Market already exists");
        require(sides.length >= 2, "Must have at least 2 sides");
        _markets[marketId].bettingPeriodEnd = bettingPeriodEnd;
        _markets[marketId].exists = true;

        for(uint256 i = 0; i < sides.length; i++) {
            // TODO does side == bytes32(0) cause issues?
            _markets[marketId].sideExists[sides[i]] = true;
        }
        emit OpenMarket(marketId, sides, bettingPeriodEnd);
    }

    function setMarketWinner(bytes32 marketId, bytes32 winner) external onlyOwner {
        _validateMarketIsOperational(marketId, winner);
        require(_markets[marketId].winningSide == NO_WINNER, "Winner already set");
        _markets[marketId].winningSide = winner;
        emit WinnerSet(marketId, winner);
    }

    /// Throws if a bet cannot be placed for a given market and sideId
    function validateBet(bytes32 marketId, bytes32 sideId) external view {
        _validateMarketIsOperational(marketId, sideId);
        require(!isBettingOver(marketId), "Betting is over");
    }

    /// Throws if a bet cannot be claimed for a given market and side Id
    function validateClaim(bytes32 marketId, bytes32 sideId) external view {
        _validateMarketIsOperational(marketId, sideId);
        require(isBettingOver(marketId), "Betting is not over");

        OracleMarket storage market = _markets[marketId];
        require(market.winningSide != NO_WINNER, "Market winner not set");
        require(market.winningSide == sideId, "Side is not winner");
    }

    /// Throws if a bet cannot be withdrawn for a given market Id
    function validateWithdraw(bytes32 marketId) external view {
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
    function isBettingOver(bytes32 marketId) public view returns (bool) {
        return block.timestamp >= _markets[marketId].bettingPeriodEnd;
    }
}
