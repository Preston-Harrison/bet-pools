// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

struct Market {
    mapping(bytes => uint256) pathToPayout;
    mapping(bytes => uint256) absolutePathToReserve;
    uint256 maxReserve;
}

/// all the arrays here are assumed to be sorted & unique
/// this has to be super gas effecient
library MarketLogic {
    using MarketLogic for Market;

    /// Returns true if a proposition is unique and sorted, false otherwise
    /// The definition of unique means that no two elements of the array
    /// are the same. The definition of sorted means that each element,
    /// when casted to a uint256, is greater than the previous element
    function isUniqueAndSorted(bytes32[] calldata propositions)
        internal
        pure
        returns (bool)
    {
        // dont want to check cuz gas, but propositions.length must be greater 1

        bytes32 previous = propositions[0];
        for (uint256 i = 1; i < propositions.length; i++) {
            // if greater than, its not sorted
            // if equal than, its not unique
            if (uint256(previous) >= uint256(propositions[i])) {
                return false;
            }
            previous = propositions[i];
        }
        return true;
    }

    function insertPayout(
        Market storage market,
        bytes32[] calldata propositions
    ) internal {
        
    }

    /// Since the arrays are sorted in ascending order, a subset always
    /// has a starting element gte to the start of the propositions,
    /// and and ending element lte to the end of the propositions
    function isSubsetOfArray(
        bytes32[] calldata subset,
        bytes32[] calldata propositions
    ) internal pure returns (bool) {
        return
            subset.length != propositions.length &&
            uint256(subset[0]) >= uint256(propositions[0]) &&
            uint256(subset[subset.length - 1]) <=
            uint256(propositions[propositions.length - 1]);
    }

    /// Since the arrays are sorted in ascending order, a superset always
    /// has a starting element lte to the start of the propositions,
    /// and and ending element gte to the end of the propositions
    function isSupersetOfArray(
        bytes32[] calldata superset,
        bytes32[] calldata propositions
    ) internal pure returns (bool) {
        return
            superset.length != propositions.length &&
            uint256(superset[0]) <= uint256(propositions[0]) &&
            uint256(superset[superset.length - 1]) >=
            uint256(propositions[propositions.length - 1]);
    }

    function getPayoutKey(bytes32[] calldata propositions)
        private
        pure
        returns (bytes memory)
    {
        return abi.encode(propositions);
    }
}
