// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Transferrer.sol";
import "./Roles.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

enum FeeType {
    Deposit,
    Withdraw,
    Bet
}

abstract contract FeeDistribution is Transferrer, Roles {
    using Address for address;
    using SafeERC20 for IERC20;

    /// All deposit/withdraw fees go to the factory
    uint256 public constant DEPOSIT_WITHDRAW_FEE = 0.001 * 1 ether; // 0.1%

    /// Bet fees are taken and distributed to the liquidity providers and
    /// the adminFeeRecipient.
    uint256 public constant BET_FEE = 0.05 * 1 ether; // 5%
    /// The percent that goes to the liquidity providers
    uint256 public constant LP_FEE = 0.8 * 1 ether; // 80%
    /// The percent that goes to the adminFeeRecipient
    uint256 public constant ADMIN_FEE = 0.2 * 1 ether; // 20%

    /// The recipient of admin fees
    address public adminFeeReceipient;
    /// The address of the deployer of this contract
    address private immutable _factory;

    event ChangeFeeRecipient(address feeReceipient);

    constructor(address adminFeeReceipient_) {
        require(
            adminFeeReceipient_ != address(0),
            "Admin fee recipient cannot be zero"
        );
        require(msg.sender.isContract(), "Msg.sender must be factory");
        adminFeeReceipient = adminFeeReceipient_;
        _factory = msg.sender;
    }

    /// Sets the admin fee recipient
    function setFeeRecipient(address adminFeeReceipient_)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(
            adminFeeReceipient_ != address(0),
            "Fee recipient cannot be zero"
        );
        adminFeeReceipient = adminFeeReceipient_;
        emit ChangeFeeRecipient(adminFeeReceipient_);
    }

    /// Collects fees and returns the amount after fees have been taken
    function collectFees(uint256 amount, FeeType feeType)
        internal
        returns (uint256)
    {
        if (feeType == FeeType.Deposit || feeType == FeeType.Withdraw) {
            uint256 fee = _calculateFraction(amount, DEPOSIT_WITHDRAW_FEE);
            transferOut(_factory, fee);
            return amount - fee;
        } else if (feeType == FeeType.Bet) {
            uint256 totalFee = _calculateFraction(amount, BET_FEE);
            // no need to transfer liquidty fee as it just accrues in the pool
            transferOut(
                adminFeeReceipient,
                _calculateFraction(totalFee, ADMIN_FEE)
            );
            return amount - totalFee;
        }
        revert(); // shouldn't happen
    }

    function _calculateFraction(uint256 amount, uint256 fraction)
        private
        pure
        returns (uint256)
    {
        return (amount * fraction) / 1 ether;
    }
}
