// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library Validate {
    function validateOdds(
        address signer,
        uint256 odds,
        bytes32 market,
        bytes32 side,
        uint256 expiry,
        bytes calldata signature
    ) internal pure {
        bytes memory message = abi.encodePacked(odds, market, side, expiry);
        bytes32 hash = ECDSA.toEthSignedMessageHash(keccak256(message));
        require(ECDSA.recover(hash, signature) == signer, "Invalid signature");
    }
}
