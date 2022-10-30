// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BettingPool.sol";

contract BettingPoolFactory is Ownable {
    using SafeERC20 for IERC20;
    using Address for address;

    address private immutable _bettingToken;

    mapping(address => bool) private _isBettingPool;

    event CreateBettingPool(address indexed pool, bytes32[] sides, uint256[] initialSizes, uint256 bettingPeriodEnd);

    modifier onlyBettingPool() {
        require(_isBettingPool[msg.sender]); // TODO msg
        _;
    }

    constructor(address bettingToken_) {
        require(bettingToken_.isContract(), "Betting token is not a contract");
        _bettingToken = bettingToken_;
    }

    function createBettingPool(
        bytes32[] memory sides,
        uint256[] memory initialSizes,
        uint256 bettingPeriodEnd
    ) external onlyOwner {
        address bettingPool = address(
            new BettingPool(
                _bettingToken,
                sides,
                initialSizes,
                bettingPeriodEnd
            )
        );
        _isBettingPool[bettingPool] = true;

        emit CreateBettingPool(
            bettingPool,
            sides,
            initialSizes,
            bettingPeriodEnd
        );
    }

    function setBettingPoolBalance(uint256 payouts) external onlyBettingPool {
        uint256 balance = IERC20(_bettingToken).balanceOf(msg.sender);
        if (balance < payouts) {
            IERC20(_bettingToken).safeTransfer(msg.sender, payouts - balance);
        } else if (payouts < balance) {
            IERC20(_bettingToken).safeTransferFrom(
                msg.sender,
                address(this),
                balance - payouts
            );
        }
    }

    function setWinningSide(address bettingPool, bytes32 side)
        external
        onlyOwner
    {
        require(_isBettingPool[bettingPool]); // TODO msg
        BettingPool(bettingPool).setWinningSide(side);
    }

    function allowWithdraws(address bettingPool) external onlyOwner {
        require(_isBettingPool[bettingPool]); // TODO msg
        BettingPool(bettingPool).allowWithdraws();
    }
}
