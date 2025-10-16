// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockAToken
 * @notice Mock aToken (interest-bearing token) for testing
 * @dev In real Aave, aToken balance grows automatically via rebasing
 * For testing, we just use a normal ERC20
 */
contract MockAToken is ERC20 {
    
    address public pool;
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        pool = msg.sender; // Pool will be the deployer
    }
    
    /**
     * @notice Mint aTokens (only pool can call)
     */
    function mint(address to, uint256 amount) external {
        require(msg.sender == pool, "Only pool");
        _mint(to, amount);
    }
    
    /**
     * @notice Burn aTokens (only pool can call)
     */
    function burn(address from, uint256 amount) external {
        require(msg.sender == pool, "Only pool");
        _burn(from, amount);
    }
    
    /**
     * @notice Set pool address (for testing setup)
     */
    function setPool(address _pool) external {
        pool = _pool;
    }
    
    /**
     * @notice Override decimals to match USDC (6 decimals)
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}