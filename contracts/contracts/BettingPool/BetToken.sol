// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./LiquidityPool.sol";

struct Bet {
    /// The market in which this bet resides
    bytes32 market;
    /// The payout of the bet
    uint256 payout;
    /// The side the bet is on
    bytes32 side;
}

abstract contract BetToken is ERC721 {
    /// Mapping of id to bets
    mapping(uint256 => Bet) private _bets;

    /// Counter for mints
    uint256 private _counter;

    constructor() ERC721("Recorded Bet", "BET") {}

    /// Mints a bet to better.
    /// @param market the market of the bet
    /// @param payout the payout of the bet
    /// @param side the side of the bet
    function mintBet(
        address better,
        bytes32 market,
        uint256 payout,
        bytes32 side
    ) internal {
        _counter++;
        _bets[_counter] = Bet(market, payout, side);
        _mint(better, _counter);
    }

    /// Burns a bet
    function burnBet(uint256 betId) internal {
        _burn(betId);
        delete _bets[betId];
    }

    /// Returns a bet
    function getBet(uint256 betId) public view returns (Bet memory) {
        return _bets[betId];
    }
}
