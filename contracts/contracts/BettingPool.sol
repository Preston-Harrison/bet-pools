// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BettingPoolFactory.sol";

struct Bet {
    address better;
    uint256 amount;
    uint256 payout;
    bytes32 side;
}

struct Side {
    uint256 size;
    uint256 payouts;
}

contract BettingPool {
    using Address for address;
    using SafeERC20 for IERC20;

    address private immutable _self;
    address private immutable _bettingFactory;
    address private immutable _bettingToken;
    uint256 private immutable _bettingPeriodEnd;

    uint256 private _prevBalance;
    mapping(bytes32 => Bet) private _bets;

    mapping(bytes32 => Side) private _sides;
    uint256 private _totalSideSize;
    bytes32 private _winningSide;
    bool private _canWithdraw;

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

    modifier onlyFactory() {
        require(msg.sender == _bettingFactory);
        _;
    }

    modifier onlyValidSide(bytes32 side) {
        require(_sides[side].size > 0);
        _;
    }

    constructor(
        address bettingToken_,
        bytes32[] memory sides_,
        uint256[] memory initialSizes,
        uint256 bettingPeriodEnd_
    ) {
        require(bettingToken_.isContract(), "Betting token is not a contract");
        require(msg.sender.isContract(), "msg.sender is not factory");
        require(sides_.length <= 255, "Must be less than 256 sides");
        require(sides_.length >= 2, "Must have at least 2 sides");
        require(initialSizes.length == sides_.length); // TODO msg
        require(
            bettingPeriodEnd_ > block.timestamp,
            "Betting must end in the future"
        );

        _bettingToken = bettingToken_;
        _bettingPeriodEnd = bettingPeriodEnd_;
        _bettingFactory = msg.sender;
        _self = address(this);
        _canWithdraw = false;

        for (uint256 i = 0; i < sides_.length; i++) {
            require(sides_[i] != bytes32(0)); // TODO msg
            require(initialSizes[i] > 0); // TODO msg

            _increaseSide(sides_[i], initialSizes[i], 0);
        }
    }

    function _transferIn() private returns (uint256 amount) {
        assert(block.timestamp < _bettingPeriodEnd);
        uint256 nextBalance = IERC20(_bettingToken).balanceOf(_self);
        amount = nextBalance - _prevBalance;
        _prevBalance = nextBalance;
    }

    function _increaseSide(
        bytes32 side,
        uint256 size,
        uint256 payout
    ) private {
        _sides[side].size += size;
        _sides[side].payouts += payout;
        _totalSideSize += size;
    }

    function _transferOut(uint256 _amount, address _receiver) private {
        assert(block.timestamp > _bettingPeriodEnd);
        IERC20(_bettingToken).safeTransfer(_receiver, _amount);
    }

    function _getPayout(uint256 amount, bytes32 side)
        private
        pure
        returns (uint256)
    {
        uint256 size = _sides[side].size;
        return amount + (amount * (_totalSideSize - size)) / size;
    }

    function bet(
        bytes32 side,
        bytes32 betKey,
        address better
    ) external onlyValidSide(side) {
        require(block.timestamp < _bettingPeriodEnd); // TODO msg
        require(_bets[betKey].better == address(0)); // TODO msg

        uint256 amount = _transferIn();
        require(amount > 0, "Bet cannot be zero");

        _increaseSide(side, amount, 0);
        uint256 payout = _getPayout(amount, side);
        _increaseSide(side, 0, payout);

        _bets[betKey] = Bet(better, amount, payout, side);
        emit BetPlaced(betKey, better, amount, payout, side);
    }

    function claim(bytes32 betKey) external {
        require(_winningSide != bytes32(0)); // TODO msg
        require(_bets[betKey].better == msg.sender); // TODO msg
        require(_bets[betKey].side == _winningSide); // TODO msg
        require(block.timestamp > _bettingPeriodEnd); // TODO msg
        require(!_canWithdraw); // TODO msg

        _transferOut(_bets[betKey].payout, msg.sender);
        emit PayoutClaimed(betKey);
        delete _bets[betKey];
    }

    function withdraw(bytes32 betKey) external {
        require(_canWithdraw); // TODO msg
        require(_bets[betKey].better == msg.sender); // TODO msg

        _transferOut(_bets[betKey].payout, msg.sender);
        emit BetWithdrawn(betKey);
        delete _bets[betKey];
    }

    function allowWithdraws() external onlyFactory {
        require(!_canWithdraw); // TODO msg
        require(_winningSide == bytes32(0)); // TODO msg
        _canWithdraw = true;
        emit WithdrawalsEnabled();
    }

    function setWinningSide(bytes32 side) external onlyFactory onlyValidSide(side) {
        require(!_canWithdraw); // TODO msg
        require(_winningSide == bytes32(0)); // TODO msg

        _winningSide = side;
        emit SetWinningSide(_winningSide);

        IERC20(_bettingToken).safeApprove(_bettingFactory, type(uint256).max);
        BettingPoolFactory(_bettingFactory).setBettingPoolBalance(
            _sides[side].payouts
        );
    }
}
