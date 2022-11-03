// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Transferrer.sol";
import "./Roles.sol";
import "@openzeppelin/contracts/utils/Address.sol";

enum FeeType {
    Deposit,
    Withdraw,
    Bet
}

abstract contract FeeDistribution is Transferrer, Roles {
    using Address for address;

    /// The recipient of admin fees
    address public adminFeeReceipient;
    /// The address of the deployer of this contract
    address private immutable _factory;

    event ChangeFeeRecipient(address feeReceipient);

    constructor(address adminFeeReceipient_) {
        require(adminFeeReceipient_ != address(0), "Admin fee recipient cannot be zero");
        require(msg.sender.isContract(), "Msg.sender must be factory");
        adminFeeReceipient = adminFeeReceipient_;
        _factory = msg.sender;
    }

    /// Sets the admin fee recipient
    function setFeeRecipient(address adminFeeReceipient_)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(adminFeeReceipient_ != address(0), "Fee recipient cannot be zero");
        adminFeeReceipient = adminFeeReceipient_;
        emit ChangeFeeRecipient(adminFeeReceipient_);
    }

    /// Collects fees and returns the amount after fees have been taken
    function collectFees(uint256 amount, FeeType feeType)
        internal
        returns (uint256)
    {
        // TODO fee calculations TBD
        return amount;
    }
}
