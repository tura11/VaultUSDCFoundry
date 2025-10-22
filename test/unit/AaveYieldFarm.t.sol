// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultUSDC} from "../../src/VaultUSDC.sol";
import {AaveYieldFarm} from "../../src/AaveYieldFarm.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockAavePool} from "../mocks/MockAavePool.sol";
import {MockTokenA} from "../mocks/MockTokenA.sol";

/**
 * @title AaveYieldFarmTest
 * @notice Comprehensive test suite for AaveYieldFarm strategy contract
 * @dev Tests all functionality including deposits, withdrawals, harvesting, and edge cases
 */
contract AaveYieldFarmTest is Test {
    // ============ State Variables ============

    AaveYieldFarm public strategy;
    VaultUSDC public vault;
    MockAavePool public pool;

    ERC20Mock public usdc;
    MockTokenA public aUsdc;

    address public user;
    address public owner;

    uint256 public constant INITIAL_BALANCE = 1_000_000e6;

    // ============ Events ============

    event Deposited(uint256 amount, uint256 timestamp);
    event Withdrawn(uint256 amount, uint256 timestamp);
    event Harvested(uint256 profit, uint256 timestamp);
    event EmergencyWithdrawal(uint256 amount, uint256 timestamp);

    // ============ Setup ============

    /**
     * @notice Set up test environment before each test
     * @dev Deploys all contracts and mints initial tokens
     */
    function setUp() public {
        user = makeAddr("user");
        owner = makeAddr("owner");

        // Deploy mock tokens
        usdc = new ERC20Mock();
        usdc.mint(owner, INITIAL_BALANCE);
        usdc.mint(user, INITIAL_BALANCE);

        aUsdc = new MockTokenA();
        aUsdc.mint(owner, INITIAL_BALANCE);
        aUsdc.mint(user, INITIAL_BALANCE);

        vm.startPrank(owner);

        // Deploy vault
        vault = new VaultUSDC(usdc);
        usdc.mint(address(vault), INITIAL_BALANCE);

        // Deploy mock Aave pool
        pool = new MockAavePool(address(usdc), address(aUsdc));

        // Deploy strategy
        strategy = new AaveYieldFarm(
            address(usdc), // _asset
            address(pool), // _lendingPool
            address(aUsdc), // _aToken
            address(vault) // _vault
        );

        // Connect strategy to vault
        vault.setStrategy(address(strategy));

        vm.stopPrank();

        // Fund the pool for withdrawals
        usdc.mint(address(pool), INITIAL_BALANCE);
    }

    // ============ Constructor Tests ============

    /**
     * @notice Test constructor properly initializes all state variables
     */
    function testConstructor() public view {
        assertEq(strategy.getAssetToken(), address(usdc));
        assertEq(strategy.getLendingPool(), address(pool));
        assertEq(address(strategy.aToken()), address(aUsdc));
        assertEq(strategy.vault(), address(vault));
        assertTrue(strategy.active());
    }

    // ============ Modifier Tests - onlyVault ============

    /**
     * @notice Test onlyVault modifier reverts when non-vault calls deposit
     */
    function testOnlyVaultModifier_RevertsOnDeposit() public {
        uint256 amount = 1000e6;

        vm.prank(owner);
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__OnlyVault.selector);
        strategy.deposit(amount);

        vm.prank(user);
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__OnlyVault.selector);
        strategy.deposit(amount);
    }

    /**
     * @notice Test onlyVault modifier reverts when non-vault calls withdraw
     */
    function testOnlyVaultModifier_RevertsOnWithdraw() public {
        uint256 amount = 1000e6;

        vm.prank(owner);
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__OnlyVault.selector);
        strategy.withdraw(amount);

        vm.prank(user);
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__OnlyVault.selector);
        strategy.withdraw(amount);
    }

    /**
     * @notice Test onlyVault modifier reverts when non-vault calls harvest
     */
    function testOnlyVaultModifier_RevertsOnHarvest() public {
        vm.prank(owner);
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__OnlyVault.selector);
        strategy.harvest();

        vm.prank(user);
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__OnlyVault.selector);
        strategy.harvest();
    }

    /**
     * @notice Test onlyVault modifier allows vault to call all functions
     */
    function testOnlyVaultModifier_AllowsVault() public {
        uint256 amount = 1000e6;

        usdc.mint(address(vault), amount);
        vm.prank(address(vault));
        usdc.approve(address(strategy), amount);

        // Vault can call deposit
        vm.prank(address(vault));
        strategy.deposit(amount);

        // Vault can call withdraw
        vm.prank(address(vault));
        strategy.withdraw(amount);

        // Vault can call harvest
        vm.prank(address(vault));
        strategy.harvest();
    }

    // ============ Modifier Tests - whenActive ============

    /**
     * @notice Test whenActive modifier reverts deposit when strategy is inactive
     */
    function testWhenActiveModifier_RevertsOnDeposit() public {
        uint256 amount = 1000e6;

        // Deactivate strategy
        vm.prank(owner);
        strategy.deactivateStrategy();

        usdc.mint(address(vault), amount);
        vm.prank(address(vault));
        usdc.approve(address(strategy), amount);

        vm.prank(address(vault));
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__StrategyInactive.selector);
        strategy.deposit(amount);
    }

    /**
     * @notice Test whenActive modifier reverts harvest when strategy is inactive
     */
    function testWhenActiveModifier_RevertsOnHarvest() public {
        // Deactivate strategy
        vm.prank(owner);
        strategy.deactivateStrategy();

        vm.prank(address(vault));
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__StrategyInactive.selector);
        strategy.harvest();
    }

    /**
     * @notice Test whenActive modifier allows operations when strategy is active
     */
    function testWhenActiveModifier_AllowsWhenActive() public {
        uint256 amount = 1000e6;

        // Strategy is active
        assertTrue(strategy.active());

        usdc.mint(address(vault), amount);
        vm.prank(address(vault));
        usdc.approve(address(strategy), amount);

        // Deposit works when active
        vm.prank(address(vault));
        strategy.deposit(amount);

        // Harvest works when active
        vm.prank(address(vault));
        strategy.harvest();
    }

    // ============ Deposit Tests ============

    /**
     * @notice Test successful deposit from vault
     */
    function testDepositWorksWhenCalledByVault() public {
        uint256 amount = 1000e6;

        usdc.mint(address(vault), amount);
        vm.prank(address(vault));
        usdc.approve(address(strategy), amount);

        vm.prank(address(vault));
        uint256 deposited = strategy.deposit(amount);

        assertEq(deposited, amount);
        assertGt(strategy.balanceOf(), 0);
        assertEq(strategy.totalDeposited(), amount);
    }

    /**
     * @notice Test deposit reverts when amount is zero
     */
    function testDepositRevertZeroDeposit() public {
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), INITIAL_BALANCE);
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__ZeroDeposit.selector);
        strategy.deposit(0);
        vm.stopPrank();
    }

    /**
     * @notice Test deposit emits Deposited event
     */
    function testDepositEmitEvent() public {
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), INITIAL_BALANCE);
        vm.expectEmit(true, true, false, true);
        emit Deposited(INITIAL_BALANCE, block.timestamp);
        strategy.deposit(INITIAL_BALANCE);
        vm.stopPrank();
    }

    // ============ Withdraw Tests ============

    /**
     * @notice Test withdraw reverts when amount is zero
     */
    function testWithdrawRevertZeroAmount() public {
        vm.prank(address(vault));
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__ZeroAmount.selector);
        strategy.withdraw(0);
    }

    /**
     * @notice Test withdraw reverts when balance is insufficient
     */
    function testWithdrawRevertInsufficientBalance() public {
        uint256 amount = 1000e6;

        // No deposits made
        vm.prank(address(vault));
        vm.expectRevert(AaveYieldFarm.AaveYieldFarm__InsufficientBalance.selector);
        strategy.withdraw(amount);
    }

    /**
     * @notice Test successful withdrawal
     */
    function testWithdrawSuccess() public {
        uint256 amount = 1000e6;

        // First deposit
        usdc.mint(address(vault), amount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);

        // Then withdraw
        uint256 withdrawn = strategy.withdraw(amount);
        vm.stopPrank();

        assertEq(withdrawn, amount);
        assertEq(strategy.totalDeposited(), 0);
    }

    /**
     * @notice Test withdraw updates totalDeposited correctly when withdrawn < totalDeposited
     */
    function testWithdrawUpdatesTotalDepositedNormally() public {
        uint256 depositAmount = 1000e6;
        uint256 withdrawAmount = 400e6;

        // Setup: deposit
        usdc.mint(address(vault), depositAmount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount);

        // Check initial state
        assertEq(strategy.totalDeposited(), depositAmount);

        // Withdraw less than deposited
        strategy.withdraw(withdrawAmount);

        // totalDeposited >= withdrawn: totalDeposited -= withdrawn
        assertEq(strategy.totalDeposited(), depositAmount - withdrawAmount);
        vm.stopPrank();
    }

    /**
     * @notice Test withdraw sets totalDeposited to zero when withdrawn > totalDeposited
     * @dev This happens when yield is generated and withdrawn amount exceeds original deposit
     */
    function testWithdrawSetsToZeroWhenWithdrawnExceedsTotalDeposited() public {
        uint256 depositAmount = 1000e6;
        uint256 yield = 500e6;

        // Setup: deposit
        usdc.mint(address(vault), depositAmount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount);
        vm.stopPrank();

        // Simulate yield - mint more aTokens to strategy
        // Now balanceOf() > totalDeposited
        aUsdc.mint(address(strategy), yield);

        // Check state before withdraw
        assertEq(strategy.totalDeposited(), depositAmount);
        assertEq(strategy.balanceOf(), depositAmount + yield);

        // Withdraw everything (deposit + yield)
        vm.prank(address(vault));
        uint256 withdrawn = strategy.withdraw(depositAmount + yield);

        // withdrawn (1500e6) > totalDeposited (1000e6)
        // so totalDeposited = 0
        assertEq(withdrawn, depositAmount + yield);
        assertEq(strategy.totalDeposited(), 0);
    }

    /**
     * @notice Test multiple sequential withdrawals until balance reaches zero
     */
    function testWithdrawMultipleTimesUntilZero() public {
        uint256 depositAmount = 1000e6;

        // Setup: deposit
        usdc.mint(address(vault), depositAmount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount);

        // First withdraw - normal path
        strategy.withdraw(400e6);
        assertEq(strategy.totalDeposited(), 600e6);

        // Second withdraw - normal path
        strategy.withdraw(300e6);
        assertEq(strategy.totalDeposited(), 300e6);

        // Third withdraw - normal path, exactly zero
        strategy.withdraw(300e6);
        assertEq(strategy.totalDeposited(), 0);

        vm.stopPrank();
    }

    /**
     * @notice Test withdraw with massive yield exceeding deposit
     * @dev Edge case: tests else branch when yield >> deposit
     */
    function testWithdrawWithYieldExceedingDeposit() public {
        uint256 depositAmount = 100e6;
        uint256 massiveYield = 10000e6;

        // Setup: deposit
        usdc.mint(address(vault), depositAmount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount);
        vm.stopPrank();

        // Simulate massive yield
        aUsdc.mint(address(strategy), massiveYield);
        usdc.mint(address(pool), massiveYield); // Pool needs funds for withdrawal

        uint256 totalBalance = strategy.balanceOf();
        assertEq(totalBalance, depositAmount + massiveYield);

        // Withdraw everything
        vm.prank(address(vault));
        strategy.withdraw(totalBalance);

        // totalDeposited < withdrawn, so totalDeposited = 0
        assertEq(strategy.totalDeposited(), 0);
    }

    /**
     * @notice Test withdraw emits Withdrawn event
     */
    function testWithdrawEmitEvent() public {
        uint256 amount = 1000e6;

        usdc.mint(address(vault), amount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);

        vm.expectEmit(true, true, false, true);
        emit Withdrawn(amount, block.timestamp);
        strategy.withdraw(amount);
        vm.stopPrank();
    }

    // ============ Harvest Tests ============

    /**
     * @notice Test harvest returns zero when no profit is generated
     */
    function testHarvestNoProfit() public {
        uint256 amount = 1000e6;

        usdc.mint(address(vault), amount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);

        uint256 profit = strategy.harvest();
        vm.stopPrank();

        assertEq(profit, 0);
    }

    /**
     * @notice Test harvest correctly calculates and withdraws profit
     */
    function testHarvestWithProfit() public {
        uint256 amount = 1000e6;
        uint256 yield = 100e6;

        usdc.mint(address(vault), amount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);
        vm.stopPrank();

        // Simulate yield by minting aTokens
        aUsdc.mint(address(strategy), yield);

        vm.prank(address(vault));
        uint256 profit = strategy.harvest();

        assertEq(profit, yield);
    }

    /**
     * @notice Test harvest emits Harvested event
     */
    function testHarvestEmitEvent() public {
        uint256 amount = 1000e6;

        usdc.mint(address(vault), amount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);

        vm.expectEmit(true, true, false, true);
        emit Harvested(0, block.timestamp);
        strategy.harvest();
        vm.stopPrank();
    }

    // ============ View Function Tests ============

    /**
     * @notice Test balanceOf returns correct aToken balance
     */
    function testBalanceOf() public {
        uint256 amount = 1000e6;

        assertEq(strategy.balanceOf(), 0);

        usdc.mint(address(vault), amount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);
        vm.stopPrank();

        assertGt(strategy.balanceOf(), 0);
    }

    /**
     * @notice Test asset returns correct USDC address
     */
    function testAsset() public view {
        assertEq(strategy.asset(), address(usdc));
    }

    /**
     * @notice Test isActive returns correct strategy status
     */
    function testIsActive() public {
        assertTrue(strategy.isActive());

        vm.prank(owner);
        strategy.deactivateStrategy();

        assertFalse(strategy.isActive());
    }

    // ============ Admin Function Tests ============

    /**
     * @notice Test activating and deactivating strategy
     */
    function testActivateDeactivate() public {
        assertTrue(strategy.active());

        vm.prank(owner);
        strategy.deactivateStrategy();
        assertFalse(strategy.active());

        vm.prank(owner);
        strategy.activateStrategy();
        assertTrue(strategy.active());
    }

    /**
     * @notice Test updating vault address
     */
    function testUpdateVault() public {
        address newVault = makeAddr("newVault");

        vm.prank(owner);
        strategy.updateVault(newVault);

        assertEq(strategy.vault(), newVault);
    }

    /**
     * @notice Test updateVault reverts with zero address
     */
    function testUpdateVaultRevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid vault");
        strategy.updateVault(address(0));
    }

    /**
     * @notice Test emergency withdraw removes all funds and deactivates strategy
     */
    function testEmergencyWithdraw() public {
        uint256 amount = 1000e6;

        usdc.mint(address(vault), amount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);
        vm.stopPrank();

        uint256 balanceBefore = strategy.balanceOf();
        assertGt(balanceBefore, 0);

        vm.prank(owner);
        strategy.emergencyWithdraw();

        assertEq(strategy.balanceOf(), 0);
        assertFalse(strategy.active());
    }

    /**
     * @notice Test emergency withdraw emits EmergencyWithdrawal event
     */
    function testEmergencyWithdrawEmitsEvent() public {
        uint256 amount = 1000e6;

        usdc.mint(address(vault), amount);
        vm.startPrank(address(vault));
        usdc.approve(address(strategy), amount);
        strategy.deposit(amount);
        vm.stopPrank();

        uint256 balance = strategy.balanceOf();

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawal(balance, block.timestamp);
        strategy.emergencyWithdraw();
    }

    /**
     * @notice Test emergency withdraw with zero balance
     */
    function testEmergencyWithdrawZeroBalance() public {
        assertEq(strategy.balanceOf(), 0);

        vm.prank(owner);
        strategy.emergencyWithdraw();

        assertEq(strategy.balanceOf(), 0);
        assertFalse(strategy.active());
    }
}
