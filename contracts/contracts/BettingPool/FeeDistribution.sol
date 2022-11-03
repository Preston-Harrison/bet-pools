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

    address public feeReceipient;
    address private immutable _factory;

    event ChangeFeeRecipient(address feeReceipient);

    constructor(address feeReceipient_) {
        require(feeReceipient_ != address(0), "Fee recipient cannot be zero");
        require(msg.sender.isContract(), "Msg.sender must be factory");
        feeReceipient = feeReceipient_;
        _factory = msg.sender;
    }

    function setFeeRecipient(address feeReceipient_)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(feeReceipient_ != address(0), "Fee recipient cannot be zero");
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
