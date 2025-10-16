// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;


import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {Test} from "forge-std/Test.sol";
import {VaultUSDC} from "../../src/VaultUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockStrategy} from "../mocks/AaveStrategyMock.sol";
import {AaveYieldFarm} from "../../src/AaveYieldFarm.sol";

contract testAaveYieldFarm is Test {
    
}