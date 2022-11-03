// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Transferrer.sol";
import "./Roles.sol";

enum FeeType {
    Deposit,
    Withdraw,
    Bet
}

abstract contract FeeDistribution is Transferrer, Roles {
    address public feeReceipient;

    event ChangeFeeRecipient(address feeReceipient);

    constructor(address feeReceipient_) {
        feeReceipient = feeReceipient_;
    }

    function setFeeRecipient(address feeReceipient_)
        external
        onlyRole(ADMIN_ROLE)
    {
        feeReceipient = feeReceipient_;
        emit ChangeFeeRecipient(feeReceipient_);
    }

    function collectFees(uint256 amount, FeeType feeType)
        internal
        returns (uint256)
    {
        // TODO fee calculations TBD. Something like this, probably
        return amount;
    }
}
