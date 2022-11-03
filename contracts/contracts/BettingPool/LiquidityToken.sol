// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LiquidityToken is ERC20 {
    address private immutable _liquidityPool;

    modifier onlyLiquidityPool {
        require(msg.sender == _liquidityPool, "Unauthorized caller");
        _;
    }

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _liquidityPool = msg.sender;
    }

    function mint(address to, uint256 amount) external onlyLiquidityPool {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyLiquidityPool {
        _burn(from, amount);
    }
}