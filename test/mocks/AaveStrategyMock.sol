// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";

/**
 * @title MockStrategy
 * @notice Mock strategy for testing - simulates Aave behavior
 */
contract MockStrategy is IStrategy {
    error AaveYieldFarm__OnlyVault();
    error AaveYieldFarm__StrategyInactive();

    IERC20 public immutable assetToken;
    address public immutable vault;
    bool public active;
    uint256 public totalDeposited;

    modifier onlyVault() {
        if (msg.sender != vault) revert AaveYieldFarm__OnlyVault();
        _;
    }

    modifier whenActive() {
        if (!active) revert AaveYieldFarm__StrategyInactive();
        _;
    }

    constructor(address _asset, address _vault) {
        assetToken = IERC20(_asset);
        vault = _vault;
        active = true;
    }

    /**
     * @notice Mock deposit - just holds the tokens
     */
    function deposit(uint256 amount) external override onlyVault whenActive returns (uint256) {
        // Transfer tokens from vault to strategy
        assetToken.transferFrom(vault, address(this), amount);

        totalDeposited += amount;
        return amount;
    }

    /**
     * @notice Mock withdraw - sends tokens back to vault
     */
    function withdraw(uint256 amount) external override onlyVault returns (uint256) {
        uint256 balance = assetToken.balanceOf(address(this));
        uint256 toWithdraw = amount > balance ? balance : amount;

        // Transfer back to vault
        assetToken.transfer(vault, toWithdraw);

        if (totalDeposited >= toWithdraw) {
            totalDeposited -= toWithdraw;
        } else {
            totalDeposited = 0;
        }

        return toWithdraw;
    }

    /**
     * @notice Mock harvest - no yield in mock
     */
    function harvest() external override onlyVault whenActive returns (uint256) {
        // Mock strategy doesn't generate yield
        return 0;
    }

    /**
     * @notice Get balance
     */
    function balanceOf() external view override returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    /**
     * @notice Get asset address
     */
    function asset() external view override returns (address) {
        return address(assetToken);
    }

    /**
     * @notice Check if active
     */
    function isActive() external view override returns (bool) {
        return active;
    }

    /**
     * @notice Emergency withdraw all funds
     */
    function emergencyWithdraw() external override {
        uint256 balance = assetToken.balanceOf(address(this));
        if (balance > 0) {
            assetToken.transfer(vault, balance);
        }
        totalDeposited = 0;
        active = false;
    }

    /**
     * @notice Helper: simulate yield by minting tokens to strategy
     * @dev Only for testing - mint tokens first with usdc.mint(strategy, amount)
     */
    function simulateYield(uint256 amount) external {
        // Yield is simulated by external minting
        // This just updates tracking
        totalDeposited += amount;
    }
}
