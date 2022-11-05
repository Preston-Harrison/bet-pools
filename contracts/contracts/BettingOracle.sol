// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

struct OracleMarket {
    mapping(bytes32 => bool) sideExists;
    bytes32 winningSide;
    uint256 bettingPeriodEnd;
    bool isCancelled;
    bool exists;
}

contract BettingOracle {
    bytes32 public constant NO_WINNER = bytes32(0);

    // TODO oracle state setting
    // Maybe restrict oracle fetching to valid betting pools?

    mapping(bytes32 => OracleMarket) private _markets;

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
    function _validateMarketIsOperational(bytes32 marketId, bytes32 sideId) private view {
        require(_markets[marketId].exists, "Market does not exist");
        require(_markets[marketId].sideExists[sideId], "Side does not exist");
        require(!_markets[marketId].isCancelled, "Market is cancelled");
    }

    /// Returns whether a market betting period end has passed
    function isBettingOver(bytes32 marketId) public view returns (bool) {
        return block.timestamp >= _markets[marketId].bettingPeriodEnd;
    }
}
