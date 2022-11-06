// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./LiquidityPool.sol";

struct Bet {
    /// The market in which this bet resides
    bytes32 market;
    /// The size of the bet
    uint256 size;
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
    /// @return id the token id that was minted
    function mintBet(
        address better,
        bytes32 market,
        uint256 amount,
        uint256 payout,
        bytes32 side
    ) internal returns (uint256) {
        _counter++;
        _bets[_counter] = Bet(market, amount, payout, side);
        _mint(better, _counter);
        return _counter;
    }

    /// Burns a bet
    function burnBet(uint256 betId) internal {
        _burn(betId);
        delete _bets[betId];
    }

    /// Returns a bet
    function getBet(uint256 betId) public view returns (Bet memory) {
        require(_exists(betId), "Bet does not exist");
        return _bets[betId];
    }
}
