pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VaultUSDC} from "../../src/VaultUSDC.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockStrategy} from "../mocks/AaveStrategyMock.sol";


contract VaultUSDCFuzzTest is Test {
    VaultUSDC vault;
    ERC20Mock usdc;
    MockStrategy strategy;

    address owner;
    address user;


    uint256 public constant MAX_USDC_SUPPLY = 1_000_000e6;


    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");


        usdc = new ERC20Mock();
        
        vm.prank(owner);
        vault = new VaultUSDC(usdc);
        vm.stopPrank();


        vm.prank(owner);
        strategy = new MockStrategy(address(usdc), address(vault));
        vm.stopPrank();

        vm.prank(owner);
        vault.setStrategy(address(strategy));
        vm.stopPrank();

        usdc.mint(user, MAX_USDC_SUPPLY);

    }


    function testFuzz_Deposit(uint256 amount) public {

        vm.assume(amount > 0);
        vm.assume(amount <= MAX_USDC_SUPPLY);
        vm.assume(amount <= vault.maxDepositLimit());


        vm.startPrank(user);
        usdc.approve(address(vault), amount);

        uint256 balanceBefore = usdc.balanceOf(user);

        uint256 shares =  vault.deposit(amount, user);
        vm.stopPrank();
        

        assertLt(usdc.balanceOf(user), balanceBefore, "User balance should decrease");
        
    
        assertGt(shares, 0, "Should receive shares");
        
        
        assertEq(vault.balanceOf(user), shares, "Share balance mismatch");
        
        
        assertGt(vault.totalDeposited(), 0, "Total deposited should increase");
    }


   function testFuzz_DepositWithBound(uint256 randomAmount) public {
        
        uint256 amount = bound(randomAmount, 1, MAX_USDC_SUPPLY);

        vm.startPrank(user);
        usdc.approve(address(vault), amount);

        uint256 balanceBefore = usdc.balanceOf(user);

        uint256 expectedFee = (amount * vault.managementFee()) / 10000;
        uint256 expectedAfterFee = amount - expectedFee;

        uint256 shares = vault.deposit(amount, user);
        vm.stopPrank();

        assertApproxEqAbs(shares, expectedAfterFee, 1, "Shares should match amount after fee");
        assertEq(usdc.balanceOf(user), balanceBefore - amount, "User balance should decrease by full amount");
    }


    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawAmount) public {

        depositAmount = bound(depositAmount, 1, min(MAX_USDC_SUPPLY, vault.maxDepositLimit()));
        
    
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();
        
    
        vm.startPrank(owner);
        vault.rebalance();
        vm.stopPrank();
        
        
        uint256 maxWithdrawable = min(vault.maxWithdrawLimit(), vault.convertToAssets(shares));
        withdrawAmount = bound(withdrawAmount, 1, maxWithdrawable);
        
    
        vm.startPrank(user);
        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 userSharesBefore = vault.balanceOf(user);
        uint256 vaultBalanceBefore = usdc.balanceOf(address(vault));
        uint256 totalDepositedBefore = vault.totalDeposited();
        
    
        uint256 sharesBurned = vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();
        

        assertEq(vault.balanceOf(user), userSharesBefore - sharesBurned);
        assertEq(usdc.balanceOf(user), userBalanceBefore + withdrawAmount);
        assertLe(vault.totalDeposited(), totalDepositedBefore);
        assertGt(sharesBurned, 0);
    }



    function testFuzz_UpdateVaultParameters(uint256 maxDeposit, uint256 maxWithdraw, uint256 fee) public {
        maxDeposit = bound(maxDeposit, 1, vault.maxDepositLimit());
        maxWithdraw = bound(maxWithdraw, 1, vault.maxWithdrawLimit());
        fee = bound(fee, 0, 1000);

        vm.startPrank(owner);
        vault.updateVaultParameters(maxDeposit, maxWithdraw, fee);
        vm.stopPrank();

        assertEq(vault.maxDepositLimit(), maxDeposit);
        assertEq(vault.maxWithdrawLimit(), maxWithdraw);
        assertEq(vault.managementFee(), fee);

    }


    function testFuzz_WithdrawProfit(uint256 amount, uint256 profitMultiplier) public {
        amount = bound(amount, 1e6, MAX_USDC_SUPPLY); 
        profitMultiplier = bound(profitMultiplier, 1, 5);

        vm.startPrank(user);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();

      
        uint256 profitMint = (amount * profitMultiplier) / 10; 
    
        profitMint = min(profitMint, vault.maxWithdrawLimit());
        usdc.mint(address(vault), profitMint);

    
        uint256 userShares = vault.balanceOf(user);
        uint256 currentValue = vault.convertToAssets(userShares);
        uint256 costBasis = vault.userCostBasis(user);
       

        if (currentValue > costBasis) {
            uint256 expectedProfit = currentValue - costBasis;
        
            expectedProfit = min(expectedProfit, vault.maxWithdrawLimit());

          
            if (expectedProfit == 0) {
                return;
            }

            uint256 balanceBefore = usdc.balanceOf(user);

            vm.startPrank(user);
            uint256 sharesBurned = vault.withdrawProfit(user);
            vm.stopPrank();

            
            assertGt(sharesBurned, 0, "withdrawProfit should burn shares when profit > 0");

           
            assertApproxEqAbs(usdc.balanceOf(user), balanceBefore + expectedProfit, 1, "Profit not withdrawn");
        } else {
      
            return;
        }
    }


    function testFUzz_PauseAndEmergencyWithdraw(uint256 amount) public {
        amount = bound(amount, 1e6, MAX_USDC_SUPPLY);

        vm.startPrank(user);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();

        vm.startPrank(owner);
        vault.pause();
        assertTrue(vault.paused(), "Vault should be paused");
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        vault.emergencyWithdraw();
        uint256 ownerBalanceAfter = usdc.balanceOf(owner);

        assertGt(ownerBalanceAfter, ownerBalanceBefore, "Owner should receive vault funds");

        vault.unpause();
        assertFalse(vault.paused(), "Vault should be unpaused");
        vm.stopPrank();
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
            return a < b ? a : b;
        }





}