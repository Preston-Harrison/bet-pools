// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./LiquidityPool.sol";
import "./BetToken.sol";
import "../BettingOracle.sol";
import "./Transferrer.sol";
import "./FeeDistribution.sol";

struct Market {
    /// Mapping of side id to total payout on each side
    mapping(bytes32 => uint256) payouts;
    /// The amount this market should reserve for payouts
    /// This is set to zero after
    uint256 reserve;
    // set to true if this market exists
    bool exists;
}

contract BettingPool is LiquidityPool, BetToken {
    using Address for address;
    using SafeERC20 for IERC20;

    /// The oracle that provides betting information
    address private immutable _oracle;

    /// Mapping of market Id to market
    mapping(bytes32 => Market) private _markets;

    event OpenMarket(bytes32 indexed market);
    event SetWinningSide(bytes32 indexed market, uint256 side);

    /// Throws if the side is invalid
    modifier onlyExistingSide(bytes32 marketId, bytes32 side) {
        Market storage market = _markets[marketId];
        require(
            BettingOracle(_oracle).doesSideExist(marketId, side),
            "Invalid side ID"
        );
        _;
    }

    /// @param bettingToken The token to accept bets in
    constructor(
        address bettingToken,
        address oracle,
        address owner
    ) Roles(owner) Transferrer(bettingToken) FeeDistribution(owner) {
        require(bettingToken.isContract(), "Betting token is not a contract");
        require(oracle.isContract(), "Oracle is not contract");
        _oracle = oracle;
    }

    /// @param marketId The id of the market to create
    /// corresponds with the side id with the same index
    function openMarket(bytes32 marketId) external onlyRole(ADMIN_ROLE) {
        Market storage market = _markets[marketId];
        require(
            BettingOracle(_oracle).doesMarketExist(marketId),
            "Oracle does not recognise market"
        );
        require(
            !BettingOracle(_oracle).hasWinningSide(marketId),
            "Market already closed"
        );
        require(!market.exists, "Market already exists");

        market.exists = true;

        emit OpenMarket(marketId);
    }

    /// Returns whether a market is still open for betting.
    /// Reverts if the market does not exist
    function _isMarketOpen(bytes32 marketId) private view returns (bool) {
        require(_markets[marketId].exists, "Market non existant");
        if (BettingOracle(_oracle).hasWinningSide(marketId)) return false;
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
        bytes32 side,
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
        market.payouts[side] += payout;
        if (market.payouts[side] > market.reserve) {
            increaseReservedAmount(market.payouts[side] - market.reserve);
            market.reserve = market.payouts[side];
        }

        // since market specific logic is taken care of, mint the token
        mintBet(better, marketId, payout, side);
    }

    /// Throws if the parameters provided are not signed by someone with SIGNER_ROLE
    function _validateOdds(
        uint256 odds,
        bytes32 market,
        bytes32 side,
        uint256 expiry,
        bytes calldata signature
    ) private view {
        bytes memory message = abi.encodePacked(odds, market, side, expiry);
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(message));
        require(
            hasRole(SIGNER_ROLE, ECDSA.recover(hash, signature)),
            "Invalid signature"
        );
    }

    /// Returns the side for a market
    function getPayout(bytes32 marketId, bytes32 side)
        external
        view
        returns (uint256)
    {
        return _markets[marketId].payouts[side];
    }

    /// Returns the market details
    function getMarket(bytes32 marketId) external view returns (uint256, bool) {
        Market storage market = _markets[marketId];
        return (market.reserve, market.exists);
    }

    /// Places a bet on a side, given a unique betKey (used for claiming / withdrawing).
    /// Note the amount of the bet is calculated using the _transferIn function.
    /// @param marketId The id of the market to bet on
    /// @param side The side to back
    /// @param better The better for whom to allocate the bet to
    function bet(
        bytes32 marketId,
        bytes32 side,
        address better,
        uint256 odds,
        uint256 expiry,
        bytes calldata signature
    ) external onlyExistingSide(marketId, side) {
        require(_isMarketOpen(marketId), "Market not open");
        _validateOdds(odds, marketId, side, expiry, signature);

        uint256 amount = transferIn();
        require(amount > 0, "Bet cannot be zero");

        uint256 betAmount = collectFees(amount, FeeType.Bet);
        _createBet(marketId, better, side, betAmount, odds);
    }

    /// Claims a bet with id betId
    function claim(uint256 betId) external {
        Bet memory recordedBet = getBet(betId);
        require(!_isMarketOpen(recordedBet.market), "Market still open");
        require(
            BettingOracle(_oracle).hasWinningSide(recordedBet.market),
            "Winning side not set"
        );
        require(
            recordedBet.side ==
                BettingOracle(_oracle).getWinningSide(recordedBet.market),
            "Bet did not win"
        );
        _decreaseReservedOnMarketClose(recordedBet.market);

        uint256 payout = recordedBet.payout;
        // payout the owner of the token
        transferOut(ownerOf(betId), payout);
        // now that the user has been payed out, burn the token
        burnBet(betId);
        // since the bet is being payed out, the reserved amounts can be decreased
        decreaseReservedAmount(payout);
    }

    /// Decreases the reserved amounts for a marketId by the difference between
    /// the winning sides payout and the maximum payout side's payout.
    function _decreaseReservedOnMarketClose(bytes32 marketId) private {
        if (_markets[marketId].reserve == 0) {
            // the reserved amount has already been decreased.
            return;
        }

        bytes32 winner = BettingOracle(_oracle).getWinningSide(marketId);
        uint256 truePayout = _markets[marketId].payouts[winner];
        uint256 reservedPayout = _markets[marketId].reserve;

        _markets[marketId].reserve = 0;
        if (truePayout != reservedPayout) {
            // the reserved payout is always >= the true payout
            decreaseReservedAmount(reservedPayout - truePayout);
        }
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
