// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

struct OracleMarket {
    bytes32 winningSide;
    mapping(bytes32 => bool) sides;
    bool exists;
}

contract BettingOracle {
    bytes32 constant public NO_WINNER = bytes32(0);

    // TODO oracle state setting
    // Maybe restrict oracle fetching to valid betting pools?

    mapping(bytes32 => OracleMarket) private _markets;

    function getWinningSide(bytes32 marketId) external view returns (bytes32) {
        OracleMarket storage market = _markets[marketId];
        require(doesMarketExist(marketId), "Market does not exist");
        require(market.winningSide != NO_WINNER, "Market winner not set");
        return market.winningSide;
    }

    function hasWinningSide(bytes32 marketId) external view returns (bool) {
        OracleMarket storage market = _markets[marketId];
        require(doesMarketExist(marketId), "Market does not exist");
        return market.winningSide != NO_WINNER;
    }

    function doesMarketExist(bytes32 marketId) public view returns (bool) {
        return _markets[marketId].exists;
    }

    function doesSideExist(bytes32 marketId, bytes32 side) external view returns (bool) {
        return _markets[marketId].sides[side];
    }
}
