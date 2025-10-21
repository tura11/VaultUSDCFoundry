// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VaultUSDC} from "../../src/VaultUSDC.sol";
import {AaveYieldFarm} from "../../src/AaveYieldFarm.sol";
import {MockStrategy} from "../mocks/AaveStrategyMock.sol";
import {MockAavePool} from "../mocks/MockAavePool.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockTokenA} from "../mocks/MockTokenA.sol";


contract VaultUSDCInvariantTest is Test {
    VaultUSDC public vault;
    AaveYieldFarm public strategy;
    ERC20Mock public usdc;
    MockTokenA public aToken;
    MockAavePool public lendingPool;
    address public constant OWNER = address(0x1);
    address public constant USER1 = address(0x2);
    address public constant USER2 = address(0x3);
    address public constant USER3 = address(0x4);

    VaultHandler public handler;

    function setUp() public {
        // Inicjalizacja mocków
        usdc = new ERC20Mock();
        aToken = new MockTokenA();
        // Ustawienie decimals na 6 dla usdc i aToken
        vm.store(address(usdc), bytes32(uint256(8)), bytes32(uint256(6))); // decimals = 6
        vm.store(address(aToken), bytes32(uint256(8)), bytes32(uint256(6))); // decimals = 6
        lendingPool = new MockAavePool(address(usdc), address(aToken));

        vm.startPrank(OWNER);
        vault = new VaultUSDC(usdc);
        strategy = new AaveYieldFarm(address(usdc), address(lendingPool), address(aToken), address(vault));
        vm.stopPrank();

        // Ustawienie strategii w skarbcu
        vm.startPrank(OWNER);
        vault.setStrategy(address(strategy));

        // Przygotowanie handlera
        handler = new VaultHandler(vault, usdc, strategy, lendingPool);

        // Skierowanie wszystkich wywołań na handler
        targetContract(address(handler));
        vm.stopPrank();

        // Przygotowanie użytkowników
        vm.startPrank(OWNER);
        usdc.mint(USER1, 10_000_000e6); // 10M USDC
        usdc.mint(USER2, 10_000_000e6); // 10M USDC
        usdc.mint(USER3, 10_000_000e6); // 10M USDC
        usdc.mint(address(vault), 1_000_000e6); // Początkowe środki w skarbcu
        vm.stopPrank();

        vm.startPrank(USER1);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(USER2);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(USER3);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // Inwariant: Suma aktywów w skarbcu i strategii = totalAssets()
    function invariant_totalAssetsConsistency() public {
        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 strategyBalance = strategy.balanceOf();
        uint256 totalAssets = vault.totalAssets();
        assertEq(vaultBalance + strategyBalance, totalAssets, "Total assets mismatch");
    }

    // Inwariant: Użytkownik nie może wypłacić więcej, niż ma udziałów
    function invariant_userCannotWithdrawMoreThanBalance() public {
        uint256 user1Shares = vault.balanceOf(USER1);
        uint256 user1Assets = vault.convertToAssets(user1Shares);
        uint256 user2Shares = vault.balanceOf(USER2);
        uint256 user2Assets = vault.convertToAssets(user2Shares);
        uint256 user3Shares = vault.balanceOf(USER3);
        uint256 user3Assets = vault.convertToAssets(user3Shares);

        uint256 totalAssets = vault.totalAssets();
        assertLe(user1Assets, totalAssets, "User1 assets exceed total assets");
        assertLe(user2Assets, totalAssets, "User2 assets exceed total assets");
        assertLe(user3Assets, totalAssets, "User3 assets exceed total assets");
    }


    // Inwariant: Strategia nie przechowuje więcej, niż zdeponowano (chyba że symulujemy zyski)
    function invariant_strategyBalance() public {
        uint256 strategyBalance = strategy.balanceOf();
        uint256 totalDepositedToStrategy = strategy.totalDeposited();
        // Zyski mogą zwiększyć saldo, więc sprawdzamy czy saldo jest zgodne
        assertLe(totalDepositedToStrategy, strategyBalance, "Strategy deposited exceeds balance");
    }

}

contract VaultHandler is Test {
    VaultUSDC public vault;
    ERC20Mock public usdc;
    AaveYieldFarm public strategy;
    MockAavePool public lendingPool;
    address[] public users = [address(0x2), address(0x3), address(0x4)];
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    constructor(VaultUSDC _vault, ERC20Mock _usdc, AaveYieldFarm _strategy, MockAavePool _lendingPool) {
        vault = _vault;
        usdc = _usdc;
        strategy = _strategy;
        lendingPool = _lendingPool;
    }

    function deposit(uint256 amount, uint256 userIndex) public {
        address user = users[userIndex % users.length];
        amount = bound(amount, 1e6, vault.maxDepositLimit());

        vm.startPrank(user);
        try vault.deposit(amount, user) {
            totalDeposited += amount;
        } catch {
            // Ignorujemy nieudane depozyty
        }
        vm.stopPrank();
    }

    function withdraw(uint256 amount, uint256 userIndex) public {
        address user = users[userIndex % users.length];
        amount = bound(amount, 1e6, vault.maxWithdrawLimit());

        vm.startPrank(user);
        try vault.withdraw(amount, user, user) {
            totalWithdrawn += amount;
        } catch {
            // Ignorujemy nieudane wypłaty
        }
        vm.stopPrank();
    }

    function withdrawProfit(uint256 userIndex) public {
        address user = users[userIndex % users.length];

        vm.startPrank(user);
        try vault.withdrawProfit(user) {
            // Zapisujemy wypłatę zysku
        } catch {
            // Ignorujemy nieudane wypłaty zysku
        }
        vm.stopPrank();
    }

    function rebalance() public {
        vm.prank(vault.owner());
        try vault.rebalance() {
            // Rebalansowanie
        } catch {
            // Ignorujemy nieudane rebalansowanie
        }
    }

    function simulateYield(uint256 amount) public {
        amount = bound(amount, 0, 100_000e6); // Ograniczamy zysk do rozsądnej wartości
        vm.prank(vault.owner());
        lendingPool.simulateYield(address(strategy), amount);
    }

    function pause() public {
        vm.prank(vault.owner());
        try vault.pause() {
            // Pauza
        } catch {
            // Ignorujemy nieudaną pauzę
        }
    }

    function unpause() public {
        vm.prank(vault.owner());
        try vault.unpause() {
            // Odpauzowanie
        } catch {
            // Ignorujemy nieudane odpauzowanie
        }
    }

    function updateVaultParameters(uint256 maxDeposit, uint256 maxWithdraw, uint256 managementFee) public {
        maxDeposit = bound(maxDeposit, 1e6, 10_000_000e6);
        maxWithdraw = bound(maxWithdraw, 1e6, 1_000_000e6);
        managementFee = bound(managementFee, 0, 1000); // Max 10%
        vm.prank(vault.owner());
        try vault.updateVaultParameters(maxDeposit, maxWithdraw, managementFee) {
            // Aktualizacja parametrów
        } catch {
            // Ignorujemy nieudaną aktualizację
        }
    }

    function getUsers() public view returns (address[] memory) {
        return users;
    }
}