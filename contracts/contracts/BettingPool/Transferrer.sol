// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

abstract contract Transferrer {
    using SafeERC20 for IERC20;
    using Address for address;

    /// An internal tracker of the token balance, to be used by
    /// the _transferInPoolToken method exclusively
    uint256 private _prevBalance;

    /// The token associated with this contract
    address public immutable poolToken;

    /// The address of this contract
    address internal immutable self;

    constructor(address poolToken_) {
        require(poolToken_.isContract(), "Pool token not contract");
        poolToken = poolToken_;
        self = address(this);
    }

    /// Transfers in an amount of poolToken by checking the previous balance
    /// of the contract and comparing it to the current balance. The
    /// difference is the amount that has been transferred in.
    /// @return amount the amount that was transferred in
    function transferIn() internal returns (uint256 amount) {
        uint256 nextBalance = balanceOfSelf();
        amount = nextBalance - _prevBalance;
        _prevBalance = nextBalance;
    }

    /// Transfers out poolToken to recipient, and resets the internal previous
    /// poolToken balance record
    /// @param recipient The address to transfer the funds to
    /// @param amount The amount to send
    function transferOut(address recipient, uint256 amount) internal {
        IERC20(poolToken).safeTransfer(recipient, amount);
        _prevBalance = balanceOfSelf();
    }

    /// Returns the ERC20 token balance of this contract
    /// @return balance The token balance of this contract
    function balanceOfSelf() internal view returns (uint256) {
        return IERC20(poolToken).balanceOf(self);
    }
}