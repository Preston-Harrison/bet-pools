// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BettingPool.sol";
import "./LiquidityPool.sol";

contract BettingFactory is Ownable, LiquidityPool {
    using SafeERC20 for IERC20;
    using Address for address;

    /// The address of the token users can use to bet
    address public immutable bettingToken;
    // Mapping of addresses to whether or not they are betting pools
    mapping(address => bool) private _isBettingPool;

    event CreateBettingPool(
        address indexed pool,
        bytes32[] sides,
        uint256[] initialSizes,
        uint256 bettingPeriodEnd
    );

    /// Throws if bettingPool is not a betting pool
    modifier onlyValidBettingPool(address bettingPool) {
        require(_isBettingPool[bettingPool], "Invalid betting pool");
        _;
    }

    /// @param bettingToken_ The token users can use to bet
    constructor(address bettingToken_) LiquidityPool(bettingToken_) {
        require(bettingToken_.isContract(), "Betting token is not a contract");
        bettingToken = bettingToken_;
    }

    /// Deploys a new betting pool with the given parameters
    /// @param sides The array of side ids for the new pool
    /// @param initialSizes The array of initial sizes for the new pool. Each 
    /// element in this array corresponds with the side id with the same index
    /// @param bettingPeriodEnd The end of the betting period for the new pool
    function createBettingPool(
        bytes32[] memory sides,
        uint256[] memory initialSizes,
        uint256 bettingPeriodEnd
    ) external onlyOwner returns (address bettingPoolAddress) {
        BettingPool bettingPool = new BettingPool(
            bettingToken,
            sides,
            initialSizes,
            bettingPeriodEnd
        );
        bettingPoolAddress = address(bettingPool);
        _isBettingPool[bettingPoolAddress] = true;

        emit CreateBettingPool(
            bettingPoolAddress,
            sides,
            initialSizes,
            bettingPeriodEnd
        );
    }

    /// Sets the exact balance of a betting pool by either transferring out funds, 
    /// or transferring in funds. Only a betting pool can call this function
    /// @param payouts the required balance of the betting pool
    function setBettingPoolBalance(uint256 payouts)
        external
        onlyValidBettingPool(msg.sender)
    {
        uint256 balance = IERC20(bettingToken).balanceOf(msg.sender);
        if (balance < payouts) {
            IERC20(bettingToken).safeTransfer(msg.sender, payouts - balance);
        } else if (payouts < balance) {
            IERC20(bettingToken).safeTransferFrom(
                msg.sender,
                address(this),
                balance - payouts
            );
        }
    }

    /// Sets the winning side of a betting pool
    /// @param bettingPool The betting pool for which to set the winning side
    /// @param side The winning side
    function setWinningSide(address bettingPool, bytes32 side)
        external
        onlyOwner
        onlyValidBettingPool(bettingPool)
    {
        BettingPool(bettingPool).setWinningSide(side);
    }
    
    /// @param bettingPool The betting pool for which to allow withdraws
    function allowWithdraws(address bettingPool)
        external
        onlyOwner
        onlyValidBettingPool(bettingPool)
    {
        BettingPool(bettingPool).allowWithdraws();
    }
}
