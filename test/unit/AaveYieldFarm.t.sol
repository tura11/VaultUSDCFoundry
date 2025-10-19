// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultUSDC} from "../../src/VaultUSDC.sol";
import {AaveYieldFarm} from "../../src/AaveYieldFarm.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockAavePool} from "../mocks/MockAavePool.sol";
import {MockTokenA} from "../mocks/MockTokenA.sol";

contract testAaveYieldFarm is Test {
    // Kontrakty
    AaveYieldFarm public strategy;
    VaultUSDC public vault;
    MockAavePool public pool;
    
    // Tokeny
    ERC20Mock public usdc;
    MockTokenA public aUsdc;
    
    // Adresy
    address public user;
    address public owner;

    uint256 public constant INITIAL_BALANCE = 1_000_000e6;

    function setUp() public {
        user = makeAddr("user");
        owner = makeAddr("owner");
 

       
        usdc = new ERC20Mock();
        usdc.mint(owner, INITIAL_BALANCE);
        usdc.mint(user, INITIAL_BALANCE);

   
        aUsdc = new MockTokenA();
        aUsdc.mint(owner, INITIAL_BALANCE);
        aUsdc.mint(user, INITIAL_BALANCE);

        vm.startPrank(owner);
        
   
        vault = new VaultUSDC(usdc);
        
      
        pool = new MockAavePool(address(usdc), address(aUsdc));
        
      
        strategy = new AaveYieldFarm(
            address(usdc),   // _asset
            address(pool),   // _lendingPool
            address(aUsdc),  // _aToken
            address(vault)   // _vault
        );
        
      
        vault.setStrategy(address(strategy));
        
        vm.stopPrank();
        usdc.mint(address(pool), INITIAL_BALANCE);
    }

    function testConstructor() public {
        assertEq(strategy.getAssetToken(), address(usdc));
        assertEq(strategy.getLendingPool(), address(pool));
        assertEq(address(strategy.aToken()), address(aUsdc));
        assertEq(strategy.vault(), address(vault));
    }

    function testDepositRevertsWhenNotVault() public {
    uint256 amount = 1000e6;
    
    // ❌ Owner wywołuje strategy.deposit() bezpośrednio
    vm.prank(owner);
    vm.expectRevert(AaveYieldFarm.AaveYieldFarm__OnlyVault.selector);
    strategy.deposit(amount);
    
    // ❌ User wywołuje strategy.deposit() bezpośrednio
    vm.prank(user);
    vm.expectRevert(AaveYieldFarm.AaveYieldFarm__OnlyVault.selector);
    strategy.deposit(amount);
    }

    function testDepositWorksWhenCalledByVault() public {
        uint256 amount = 1000e6;
        
        // Setup: daj vault środki
        usdc.mint(address(vault), amount);

        vm.prank(address(vault));
        usdc.approve(address(strategy), amount);
        
        // ✅ Vault wywołuje strategy.deposit()
        vm.prank(address(vault));
        uint256 deposited = strategy.deposit(amount);
        
        assertEq(deposited, amount);
        assertGt(strategy.balanceOf(), 0);
    }

}