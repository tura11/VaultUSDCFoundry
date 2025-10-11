// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";

contract MockStrategy is IStrategy {
    IERC20 private _asset;
    uint256 public totalBalance;

    constructor(IERC20 __asset) {
        _asset = __asset;
    }

    function asset() external view override returns (address) {
        return address(_asset);
    }

    function deposit(uint256 amount) external override returns (uint256) {
        _asset.transferFrom(msg.sender, address(this), amount);
        totalBalance += amount;
        return amount;
    }

    function withdraw(uint256 amount) external override returns (uint256) {
        if (amount > totalBalance) amount = totalBalance;
        totalBalance -= amount;
        _asset.transfer(msg.sender, amount);
        return amount;
    }

    function balanceOf() external view override returns (uint256) {
        return totalBalance;
    }

    function emergencyWithdraw() external override {
        _asset.transfer(msg.sender, totalBalance);
        totalBalance = 0;
    }

    function harvest() external override returns (uint256) {
        return 0;
    }

    function isActive() external view override returns (bool) {
        return true;
    }
}
