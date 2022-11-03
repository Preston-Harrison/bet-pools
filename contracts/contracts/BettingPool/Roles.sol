// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract Roles is AccessControl {
    bytes32 constant public ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 constant public SIGNER_ROLE = keccak256("SIGNER_ROLE");

    constructor(address admin) {
        _grantRole(ADMIN_ROLE, admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(SIGNER_ROLE, ADMIN_ROLE);
    }
}