// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BettingPool.sol";

contract BettingPoolFactory is Ownable {
    using SafeERC20 for IERC20;

    address private immutable _bettingToken;

    mapping(address => bool) _isBettingPool;

    modifier onlyBettingPool {
        require(_isBettingPool[msg.sender]); // TODO msg
        _;
    }

    constructor(address bettingToken_) {
        _bettingToken = bettingToken_;
    }

    function setBettingPoolBalance(uint256 payouts) external onlyBettingPool {
        uint256 balance = IERC20(_bettingToken).balanceOf(msg.sender);

        if (balance < payouts) {
            IERC20(_bettingToken).safeTransfer(msg.sender, payouts - balance);
        } else if (payouts < balance) {
            IERC20(_bettingToken).safeTransferFrom(msg.sender, address(this), balance - payouts);
        }
    }

    function setWinningSide(address bettingPool, uint256 sideIndex) external onlyOwner {
        require(_isBettingPool[bettingPool]); // TODO msg
        BettingPool(bettingPool).setWinningSide(sideIndex);
    }
}