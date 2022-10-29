// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BettingPoolFactory.sol";

struct Bet {
    address better;
    uint256 payout;
    bytes32 side;
}

struct Side {
    bytes32 id;
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

    Side[] private _sides;
    bytes32 private _winningSide;

    event BetPlaced(
        bytes32 indexed betKey,
        address indexed better,
        uint256 amount,
        uint256 payout,
        bytes32 side
    );
    event PayoutClaimed(bytes32 indexed betKey);
    event SetWinningSide(bytes32 winningSide);

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

        for (uint256 i = 0; i < sides_.length; i++) {
            require(sides_[i] != bytes32(0)); // TODO msg
            require(initialSizes[i] > 0); // TODO msg

            _sides.push(Side(sides_[i], 0, 0));
            _sides[i].size += initialSizes[i];
        }

        assert(sides_.length == _sides.length);
    }

    function sidesNum() external view returns (uint256) {
        return _sides.length;
    }

    function getSidesData(uint256 index) external view returns (Side memory) {
        return _sides[index];
    }

    function _transferIn() private returns (uint256 amount) {
        assert(block.timestamp < _bettingPeriodEnd);
        uint256 nextBalance = IERC20(_bettingToken).balanceOf(_self);
        amount = nextBalance - _prevBalance;
        _prevBalance = nextBalance;
    }

    function _transferOut(uint256 _amount, address _receiver) private {
        assert(block.timestamp > _bettingPeriodEnd);
        IERC20(_bettingToken).safeTransfer(_receiver, _amount);
    }

    function _getTotalSideSize() private view returns (uint256 sum) {
        uint256 length = _sides.length;
        for (uint256 i = 0; i < length; i++) {
            sum += _sides[i].size;
        }
    }

    function _getPayout(
        uint256 amount,
        uint256 totalSize,
        uint256 sideSize
    ) private pure returns (uint256) {
        return amount + (amount * (totalSize - sideSize)) / sideSize;
    }

    function bet(uint256 sideIndex, bytes32 betKey) external {
        require(sideIndex < _sides.length, "Invalid sideIndex");
        require(block.timestamp < _bettingPeriodEnd); // TODO msg
        require(_bets[betKey].better == address(0)); // TODO msg

        uint256 amount = _transferIn();
        require(amount > 0, "Bet cannot be zero");

        _sides[sideIndex].size += amount;
        uint256 totalSideSize = _getTotalSideSize();
        uint256 payout = _getPayout(
            amount,
            totalSideSize,
            _sides[sideIndex].size
        );
        _sides[sideIndex].payouts += payout;

        _bets[betKey] = Bet(msg.sender, payout, _sides[sideIndex].id);
        emit BetPlaced(
            betKey,
            msg.sender,
            amount,
            payout,
            _sides[sideIndex].id
        );
    }

    function claim(bytes32 betKey) external {
        require(block.timestamp > _bettingPeriodEnd); // TODO msg
        require(_bets[betKey].better == msg.sender); // TODO msg
        require(_bets[betKey].side == _winningSide); // TODO msg

        _transferOut(_bets[betKey].payout, msg.sender);
        emit PayoutClaimed(betKey);

        delete _bets[betKey];
    }

    function setWinningSide(uint256 sideIndex) external {
        require(msg.sender == _bettingFactory); // TODO msg
        require(_winningSide == bytes32(0)); // TODO msg
        require(sideIndex < _sides.length, "Invalid sideIndex");

        assert(_sides[sideIndex].id != bytes32(0));
        _winningSide = _sides[sideIndex].id;
        emit SetWinningSide(_winningSide);

        IERC20(_bettingToken).safeApprove(_bettingFactory, type(uint256).max);
        BettingPoolFactory(_bettingFactory).setBettingPoolBalance(
            _sides[sideIndex].payouts
        );
    }
}
