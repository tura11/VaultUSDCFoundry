// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;


import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {Test} from "forge-std/Test.sol";
import {VaultUSDC} from "../../src/VaultUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockStrategy} from "../mocks/AaveStrategyMock.sol";

contract testAaveYieldFarm is Test {
    ERC20Mock usdc;
    VaultUSDC public vault;
    MockStrategy public strategy;

    address user;
    address owner;

    function setUp() public {

        user = makeAddr("user");
        owner = makeAddr("owner");
        usdc = new ERC20Mock();
        vm.prank(owner);
        vault = new VaultUSDC(usdc);
        vm.stopPrank();


        strategy = new MockStrategy(address(usdc), address(vault));

        vm.prank(owner);
        vault.setStrategy(address(strategy));
        vm.stopPrank();
    }
}