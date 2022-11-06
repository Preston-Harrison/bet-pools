// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./LiquidityToken.sol";
import "./Roles.sol";
import "./FeeDistribution.sol";
import "./Transferrer.sol";

abstract contract LiquidityPool is Transferrer, FeeDistribution {
    using Address for address;

    /// The liquidity token for this contract
    address public immutable liquidityToken;

    /// The minimum balance this liquidity pool can reach
    uint256 private _reservedAmount;

    event Deposit(address indexed account, uint256 amountIn, uint256 amountOut);
    event Withdraw(
        address indexed account,
        uint256 amountIn,
        uint256 amountOut
    );
    event IncreaseReservedAmount(uint256 amount);
    event DecreaseReservedAmount(uint256 amount);

    constructor() {
        liquidityToken = address(
            new LiquidityToken("BET Pool", "sBET", ERC20(poolToken).decimals())
        );
    }

    /// Returns the reserved amounts
    function getReservedAmount() external view returns (uint256) {
        return _reservedAmount;
    }

    /// Increases the reserved amount
    function increaseReservedAmount(uint256 amount) internal {
        _reservedAmount += amount;
        emit IncreaseReservedAmount(amount);
    }

    /// Decreases the reserved amount
    function decreaseReservedAmount(uint256 amount) internal {
        _reservedAmount -= amount;
        emit DecreaseReservedAmount(amount);
    }

    /// Returns the amount of non-reserved liquidity in the pool
    function getFreeBalance() internal view returns (uint256) {
        return balanceOfSelf() - _reservedAmount;
    }

    /// Calculates the amount of liquidityToken equal to depositAmount of poolToken
    function calculateLiquidityTokenForDeposit(uint256 depositAmount)
        internal
        view
        returns (uint256)
    {
        uint256 liquidityTokenSupply = IERC20(liquidityToken).totalSupply();
        if (liquidityTokenSupply == 0) return depositAmount;
        return (depositAmount * liquidityTokenSupply) / getFreeBalance();
    }

    /// Calculates the amount of poolToken equal to depositAmount of liquidityToken
    function calculatePoolTokenForWithdraw(uint256 withdrawAmount)
        internal
        view
        returns (uint256)
    {
        uint256 liquidityTokenSupply = IERC20(liquidityToken).totalSupply();
        return (withdrawAmount * getFreeBalance()) / liquidityTokenSupply;
    }

    /// Deposits an amount of pool token and transfers the equal amount of
    /// liquidityToken to msg.sender
    function deposit() external {
        uint256 amount = transferIn();
        require(amount > 0, "Cannot deposit zero");
        // always collect fees in poolToken
        uint256 amountAfterFees = collectFees(amount, FeeType.Deposit);

        uint256 amountOut = calculateLiquidityTokenForDeposit(amountAfterFees);
        LiquidityToken(liquidityToken).mint(msg.sender, amountOut);
        emit Deposit(msg.sender, amount, amountOut);
    }

    /// Withdraws an amount of pool token by burning an equal amount of
    /// liquidityToken from msg.sender, and transferring the poolToken to
    /// the msg.sender
    /// @param amount the amount of liquidityToken to burn
    function withdraw(uint256 amount) external {
        require(amount > 0, "Cannot withdraw zero");
        LiquidityToken(liquidityToken).burn(msg.sender, amount);

        uint256 poolTokenAmount = calculatePoolTokenForWithdraw(amount);
        // always collect fees in poolToken
        uint256 amountOut = collectFees(poolTokenAmount, FeeType.Withdraw);
        transferOut(msg.sender, amountOut);
        emit Withdraw(msg.sender, amount, amountOut);
    }
}
