// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VaultUSDC} from "../../src/VaultUSDC.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract testVaultUSDC is Test {

     event DepositExecuted(address indexed user, address indexed receiver, uint256 assetsDeposited, uint256 sharesReceived, uint256 managementFeeCharged, uint256 timestamp);
     event WithdrawalExecuted(address indexed user, address indexed receiver, address indexed shareOwner, uint256 assetsWithdrawn, uint256 sharesBurned, uint256 timestamp);


    ERC20Mock usdc;
    VaultUSDC vault;
    address user;
    address owner;
    uint256 public constant INITIAL_BALANCE = 1000000e6;


    function setUp() public {
        user = makeAddr("user");
        owner = makeAddr("owner");

        usdc = new ERC20Mock();
        usdc.mint(user, INITIAL_BALANCE);

        vm.startPrank(owner);
        vault = new VaultUSDC(usdc);
        vm.stopPrank();

    }

    function testConstructor() public {
        assertEq(vault.name(), "VaultUSDC");
        assertEq(vault.symbol(), "vUSDC");
        assertEq(vault.maxDepositLimit(), INITIAL_BALANCE);
        assertEq(vault.maxWithdrawLimit(), 100000e6);
        assertEq(vault.managementFee(), 200);
        assertEq(vault.totalDeposited(), 0);
    }


    function testDepositRevert() public {
        vm.startPrank(user);
        vm.expectRevert(VaultUSDC.VaultUSDC__DepositExceedsLimit.selector);
        vault.deposit(10000000e6, msg.sender);
        vm.stopPrank();
    }
    function testModifierRevertZeroAmount() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vm.expectRevert(VaultUSDC.VaultUSDC__ZeroAmount.selector);
        vault.deposit(0, msg.sender);
    }

    function testModifierRevertInvalidAddress() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        user = address(0);
        vm.expectRevert(VaultUSDC.VaultUSDC__InvalidReceiver.selector);
        vault.deposit(INITIAL_BALANCE, user);
        vm.stopPrank();
    }


    function testDepositProperlyAddAssetsAndUsers() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE, msg.sender);
        uint256 expectedTotalDeposited = 980000e6;
        assertEq(vault.totalDeposited(), expectedTotalDeposited); // after fee
        assertEq(vault.userTotalDeposited(msg.sender), expectedTotalDeposited); // its total value of deposited assets with no fee.
        assertEq(vault.totalUsers(), 1); 
        assertEq(vault.userFirstDepositTime(msg.sender), block.timestamp);
        vm.stopPrank();
    }

 
    function testDepositEmitEvent() public {
        
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);

        vm.expectEmit(true, true, false, true);
        emit VaultUSDC.DepositExecuted(
            user,
            user,
            INITIAL_BALANCE,
            980000e6,
            20000e6,
            block.timestamp
        );

        vault.deposit(INITIAL_BALANCE, user);
        vm.stopPrank();

    }


    function testWithdrawRevert() public {
        vm.startPrank(user);
        vm.expectRevert(VaultUSDC.VaultUSDC__WithdrawExceedsLimit.selector);
        vault.withdraw(10000000e6, user, user);
        vm.stopPrank();
    }


    function testWithdrawProperlyRemoveAssets() public {
    vm.startPrank(user);
    usdc.approve(address(vault), INITIAL_BALANCE);

    vault.deposit(INITIAL_BALANCE, user);

    vault.approve(address(vault), 100000e6);

    vault.withdraw(100000e6, user, user);

    assertEq(vault.totalDeposited(), 980000e6 - 100000e6);
    assertEq(vault.userTotalDeposited(user), 980000e6);
    assertEq(vault.totalUsers(), 1);
    assertEq(vault.userTotalWithdrawn(user), 100000e6);
    vm.stopPrank();
}




function testWithdrawEmitEvent() public {
    vm.startPrank(user);
    usdc.approve(address(vault), INITIAL_BALANCE);

    vault.deposit(INITIAL_BALANCE, user);

    vm.expectEmit(true, true, false, true);
    emit VaultUSDC.WithdrawalExecuted(
        user,
        user,
        user,
        100000e6,
        100000e6,
        block.timestamp
    );

    vault.withdraw(100000e6, user, user);
    vm.stopPrank();
    }







    




  
}

