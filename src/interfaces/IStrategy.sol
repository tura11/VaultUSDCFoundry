// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {VaultUSDC} from "../VaultUSDC.sol";

interface IStrategy {
    function deposit(uint256 amount) external returns (uint256);
    function withdraw(uint256 amount) external returns (uint256);
    function harvest() external returns (uint256);
    function balanceOf() external view returns (uint256);
    function asset() external view returns (address);
    function isActive() external view returns (bool);
    function emergencyWithdraw() external;
}
