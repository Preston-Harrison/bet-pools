// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "./LiquidityToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract LiquidityPool is Ownable {
    using SafeERC20 for IERC20;
    using Address for address;

    /// The token liquidity providers stake
    address public immutable poolToken;
    /// The liquidity token for this contract
    address public immutable liquidityToken;
    /// The address of this contract
    address internal immutable self;

    /// The maximum fee
    uint256 private constant MAX_FEE = 1 ether;
    /// The fee for depositing tokens, as a fraction of 1 ether
    uint256 public fee;
    /// The account that will receive fees
    address public feeReceipient;

    /// An internal tracker of the poolToken balance, to be used by
    /// the _transferInPoolToken method exclusively
    uint256 private _prevBalance;
    /// The minimum balance this liquidity pool can reach
    uint256 private _reservedAmount;

    event Deposit(address indexed account, uint256 amountIn, uint256 amountOut);
    event Withdraw(
        address indexed account,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feeOut
    );
    event SetFee(uint256 fee);
    event IncreaseReservedAmount(uint256 amount);
    event DecreaseReservedAmount(uint256 amount);

    /// @param poolToken_ The token liquidity providers stake
    constructor(address poolToken_) {
        require(poolToken_.isContract(), "PoolToken is not contract");

        poolToken = poolToken_;
        self = address(this);
        feeReceipient = owner();
        liquidityToken = address(new LiquidityToken("BET Pool", "sBET"));
    }

    /// Sets the fee as a fraction of 1 ether
    /// @param fee_ The new fee
    function setFee(uint256 fee_) external onlyOwner {
        require(fee_ <= MAX_FEE, "");
        require(fee != fee_, "Prevented null change");
        fee = fee_;
        emit SetFee(fee_);
    }

    /// @param amount The amount to calculate the fee for
    /// @return fee The fee that should be collected from amount
    function _calculateFee(uint256 amount) private view returns (uint256) {
        return (amount * fee) / 1 ether;
    }

    /// Transfers in an amount of poolToken by checking the previous balance
    /// of the contract and comparing it to the current balance. The
    /// difference is the amount that has been transferred in.
    /// @return amount the amount that was transferred in
    function transferIn() internal returns (uint256 amount) {
        uint256 nextBalance = IERC20(poolToken).balanceOf(self);
        amount = nextBalance - _prevBalance;
        _prevBalance = nextBalance;
    }

    /// Transfers out poolToken to recipient, and resets the internal previous
    /// poolToken balance record
    /// @param recipient The address to transfer the funds to
    /// @param amount The amount to send
    function transferOut(address recipient, uint256 amount) internal {
        IERC20(poolToken).safeTransfer(recipient, amount);
        _prevBalance = _balanceOfSelf(poolToken);
        assert(_prevBalance >= _reservedAmount);
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
        return _balanceOfSelf(poolToken) - _reservedAmount;
    }

    /// Calculates the amount of liquidityToken equal to depositAmount of poolToken
    function _calculateLiquidityTokenForDeposit(uint256 depositAmount)
        private
        view
        returns (uint256)
    {
        uint256 liquidityTokenSupply = IERC20(liquidityToken).totalSupply();
        return (depositAmount * liquidityTokenSupply) / getFreeBalance();
    }

    /// Calculates the amount of poolToken equal to depositAmount of liquidityToken
    function _calculatePoolTokenForWithdraw(uint256 withdrawAmount)
        private
        view
        returns (uint256)
    {
        uint256 liquidityTokenSupply = IERC20(liquidityToken).totalSupply();
        return (withdrawAmount * getFreeBalance()) / liquidityTokenSupply;
    }

    /// Returns the ERC20 token balance of this contract
    /// @param token The token to get the balance for
    /// @return balance The token balance of this contract
    function _balanceOfSelf(address token) private view returns (uint256) {
        return IERC20(token).balanceOf(self);
    }

    /// Deposits an amount of pool token and transfers the equal amount of
    /// liquidityToken to msg.sender
    function deposit() external {
        uint256 amount = transferIn();
        require(amount > 0, "Cannot deposit zero");

        uint256 amountOut = _calculateLiquidityTokenForDeposit(amount);
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

        uint256 amountOut = _calculatePoolTokenForWithdraw(amount);
        uint256 feeOut = _calculateFee(amountOut);
        transferOut(msg.sender, amountOut - feeOut);
        transferOut(feeReceipient, feeOut);
        emit Withdraw(msg.sender, amount, amountOut - feeOut, feeOut);
    }
}
