// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAaveLendingPool} from "../../src/interfaces/AaveLendingPool.sol";

/**
 * @title MockAavePool
 * @notice Mock implementation of Aave Lending Pool for testing
 */
contract MockAavePool is IAaveLendingPool {
    
    IERC20 public asset;
    IERC20 public aToken;
    
    // Track deposits per user
    mapping(address => uint256) public deposits;
    
    constructor(address _asset, address _aToken) {
        asset = IERC20(_asset);
        aToken = IERC20(_aToken);
    }
    
    /**
     * @notice Mock deposit - transfers asset and mints aTokens
     */
    function deposit(
        address assetAddress,
        uint256 amount,
        address onBehalfOf,
        uint16 /* referralCode */
    ) external override {
        require(assetAddress == address(asset), "Wrong asset");
        
        // Transfer assets from user
        asset.transferFrom(msg.sender, address(this), amount);
        
        // Mint aTokens to user (1:1 ratio initially)
        deposits[onBehalfOf] += amount;
        
        // In real Aave, aTokens would be minted
        // Here we'll transfer from the mock aToken contract
        aToken.transfer(onBehalfOf, amount);
    }
    
    /**
     * @notice Mock withdraw - burns aTokens and returns asset
     */
    function withdraw(
        address assetAddress,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        require(assetAddress == address(asset), "Wrong asset");
        
        uint256 toWithdraw = amount;
        
        // Handle type(uint256).max (withdraw all)
        if (amount == type(uint256).max) {
            toWithdraw = deposits[msg.sender];
        }
        
        require(deposits[msg.sender] >= toWithdraw, "Insufficient balance");
        
        // Update deposits
        deposits[msg.sender] -= toWithdraw;
        
        // Transfer aTokens back (burn)
        aToken.transferFrom(msg.sender, address(this), toWithdraw);
        
        // Transfer assets to recipient
        asset.transfer(to, toWithdraw);
        
        return toWithdraw;
    }
    
    /**
     * @notice Mock getReserveData
     */
    function getReserveData(address /* assetAddress */) 
        external 
        view 
        override 
        returns (uint256) 
    {
        // Return available liquidity
        return asset.balanceOf(address(this));
    }
    
    /**
     * @notice Helper: Simulate yield by minting more aTokens
     */
    function simulateYield(address user, uint256 yieldAmount) external {
        // Mint additional aTokens to simulate yield
        aToken.transfer(user, yieldAmount);
    }
}