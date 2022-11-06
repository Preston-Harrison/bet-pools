// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BettingFactory.sol";
import "./BettingPool/BettingPool.sol";
import "./BettingPool/LiquidityPool.sol";

contract BettingRouter {
    using Address for address;
    using SafeERC20 for IERC20;

    /// Address of the betting factory
    BettingFactory immutable public bettingFactory;
    /// Address of this contract
    address immutable private _self;

    constructor(address bettingFactory_) {
        require(bettingFactory_.isContract(), "Betting factory not contract");
        bettingFactory = BettingFactory(bettingFactory_);
        _self = address(this);
    }

    /// Transfers in an amount of a token
    function _transferIn(address token, uint256 amount) private {
        IERC20(token).safeTransferFrom(msg.sender, _self, amount);
    }

    /// Places a bet on behalf of msg.sender
    /// @param bettingPool the pool in which to place the bet
    /// @param marketId the market in which to place the bet
    /// @param side the side to bet on
    /// @param amount the amount to bet
    /// @param minOdds the minimum odds acceptable for this bet
    /// @param odds the odds for this bet
    /// @param expiry the expiry time for the odds for this bet
    /// @param signature the signature validating the odds are valid
    /// for the betting pool
    function bet(
        address bettingPool,
        bytes32 marketId,
        bytes32 side,
        uint256 amount,
        uint256 minOdds,
        uint256 odds,
        uint256 expiry,
        bytes calldata signature
    ) external {
        // This also checks that the betting pool exists as getBettingPool reverts
        // if the pool does not exist
        address token = bettingFactory.getBettingPool(bettingPool).token;
        BettingPool pool = BettingPool(bettingPool);
        _transferIn(token, amount);

        // Transfer the bet the betting pool, and place the bet
        IERC20(token).safeTransfer(bettingPool, amount);
        uint256 betId = pool.bet(
            marketId,
            side,
            minOdds,
            odds,
            expiry,
            signature
        );
        // transfer the bet erc721 back to the user
        pool.safeTransferFrom(_self, msg.sender, betId);
    }

    /// Allows multiple bets to be claimed in the same transaction
    function batchClaim(
        address[] calldata bettingPools,
        uint256[] calldata betIds
    ) public {
        require(bettingPools.length == betIds.length, "Array lengths differ");
        for (uint256 i = 0; i < betIds.length; i++) {
            BettingPool(bettingPools[i]).claimBet(betIds[i]);
        }
    }

    /// Allows multiple bets to be withdrawn in the same transaction
    function batchWithdraw(
        address[] calldata bettingPools,
        uint256[] calldata betIds
    ) public {
        require(bettingPools.length == betIds.length, "Array lengths differ");
        for (uint256 i = 0; i < betIds.length; i++) {
            BettingPool(bettingPools[i]).withdrawBet(betIds[i]);
        }
    }

    /// Deposits into a betting pool and transfers the liqudity tokens to the msg.sender
    /// @param bettingPool the betting pool to deposit into
    /// @param amount the amount to deposit
    /// @param minOut the minimum amount of the pools liquidity token to receive
    function deposit(
        address bettingPool,
        uint256 amount,
        uint256 minOut
    ) external {
        address token = bettingFactory.getBettingPool(bettingPool).token;
        BettingPool pool = BettingPool(bettingPool);
        _transferIn(token, amount);

        IERC20(token).safeTransfer(bettingPool, amount);
        uint256 amountOut = pool.deposit();
        require(amountOut > minOut, "Insufficient amount out");
        IERC20(pool.liquidityToken()).safeTransfer(msg.sender, amountOut);
    }

    /// Withdraws from a pool and transfers the pool token to the msg.sender
    /// @param bettingPool the betting pool to withdraw from
    /// @param amount the amount to withdraw
    /// @param minOut the minimum amount of the pool token to receive
    function withdraw(
        address bettingPool,
        uint256 amount,
        uint256 minOut
    ) external {
        address token = bettingFactory.getBettingPool(bettingPool).token;
        BettingPool pool = BettingPool(bettingPool);
        _transferIn(pool.liquidityToken(), amount);

        uint256 amountOut = pool.withdraw(amount);
        require(amountOut > minOut, "Insufficient amount out");
        IERC20(token).safeTransfer(msg.sender, amountOut);
    }
}