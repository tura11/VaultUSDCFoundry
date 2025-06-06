// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultUSDC} from "../src/VaultUSDC.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract testVaultUSDC is Test {
    MockUSDC usdc;
    VaultUSDC vault;
    address user;
    address owner;

    function setUp() public {
        user = makeAddr("user");
        owner = makeAddr("owner");

        vm.startPrank(owner);
        vault = new VaultUSDC(usdc);
        vm.stopPrank();

    }

    function testConstructor() public {
        assertEq(vault.name(), "VaultUSDC");
        assertEq(vault.symbol(), "USDC");
        assertEq(vault.maxDeposit(), 1000000e6);
        assertEq(vault.maxWithdraw(), 100000e6);
        assertEq(vault.managmentFee(), 2);
        assertEq(vault.totalDeposited(), 0);
    }



}


contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000e6); // Mint 1M USDC to test account
    }
}
