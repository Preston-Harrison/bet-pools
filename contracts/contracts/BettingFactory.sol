// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./BettingPool/BettingPool.sol";

struct BettingPoolData {
    bool exists;
    address token;
}

contract BettingFactory is Ownable {
    using Address for address;

    /// Address of the oracle
    address public oracle; // I don't think this can be changed safely

    /// Mapping of betting pool address to betting pool details
    mapping(address => BettingPoolData) private _bettingPool;

    event CreatePool(address indexed pool, address indexed token);

    /// Sets the address of the oracle. This can only be called once
    function setOracle(address oracle_) external onlyOwner {
        require(oracle == address(0), "Oracle already set");
        require(oracle_.isContract(), "Oracle is not contract");
        oracle = oracle_;
    }

    /// Creates a pool that accepts bets with token
    function createPool(address token) external returns (address) {
        require(token.isContract(), "Token not contract");
        require(oracle != address(0), "Oracle not set");

        address bettingPool = address(
            new BettingPool(token, oracle, msg.sender)
        );
        _bettingPool[bettingPool] = BettingPoolData(true, token);
        emit CreatePool(bettingPool, token);

        return bettingPool;
    }

    /// Returns a betting pool
    function getBettingPool(address pool)
        external
        view
        returns (BettingPoolData memory)
    {
        require(_bettingPool[pool].exists, "Betting pool does not exist");
        return _bettingPool[pool];
    }

    /// Returns whether an address is a betting pool
    function isBettingPool(address pool) external view returns (bool) {
        return _bettingPool[pool].exists;
    }
}
