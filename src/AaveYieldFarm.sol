// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IAaveLendingPool} from "../interfaces/AaveLedningPool.sol";





contract AaveYieldFarm is IStrategy {
    // TODO: Add Aave Yield Farm Contract
    using SafeERC20 for IERC20;
    IERC20 public immutable override asset; // USDC
    IAaveLendingPool public immutable lendingPool;


    function deposit(){}
    function withdraw(){}
    function harvest(){}
    function balanceOf() external view returns (uint256){}
    function asset() external view returns (address){}
    function isActive() external view returns (bool){}
    function emergencyWithdraw(){}


}
