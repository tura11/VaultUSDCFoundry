// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VaultUSDC} from "../../src/VaultUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockStrategy} from "../mocks/AaveStrategyMock.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";

contract testVaultUSDC is Test {
    event DepositExecuted(
        address indexed user,
        address indexed receiver,
        uint256 assetsDeposited,
        uint256 sharesReceived,
        uint256 managementFeeCharged,
        uint256 timestamp
    );
    event WithdrawalExecuted(
        address indexed user,
        address indexed receiver,
        address indexed shareOwner,
        uint256 assetsWithdrawn,
        uint256 sharesBurned,
        uint256 timestamp
    );

    MockStrategy strategy;
    ERC20Mock usdc;
    VaultUSDC vault;
    address user;
    address owner;
    uint256 public constant INITIAL_BALANCE = 1_000_000e6;

    function setUp() public {
        user = makeAddr("user");
        owner = makeAddr("owner");

        usdc = new ERC20Mock();
        

        usdc.mint(owner, INITIAL_BALANCE);
        usdc.mint(user, INITIAL_BALANCE);

        vm.startPrank(owner);
        vault = new VaultUSDC(usdc);
        vm.stopPrank();


        strategy = new MockStrategy(address(usdc), address(vault));
        
        vm.prank(owner);
        vault.setStrategy(address(strategy));
    }

    function testConstructor() public view {
        assertEq(vault.name(), "VaultUSDC");
        assertEq(vault.symbol(), "vUSDC");
        assertEq(vault.maxDepositLimit(), 1_000_000e6);
        assertEq(vault.maxWithdrawLimit(), 100_000e6);
        assertEq(vault.managementFee(), 200); // 2%
        assertEq(vault.totalDeposited(), 0);
        assertEq(vault.totalUsers(), 0);
    }

    function testDepositRevertExceedsLimit() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 10_000_000e6);
        
        vm.expectRevert(VaultUSDC.VaultUSDC__DepositExceedsLimit.selector);
        vault.deposit(10_000_000e6, user);
        vm.stopPrank();
    }

    function testDepositRevertZeroAmount() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        
        vm.expectRevert(VaultUSDC.VaultUSDC__ZeroAmount.selector);
        vault.deposit(0, user);
        vm.stopPrank();
    }

    function testDepositRevertInvalidAddress() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        
        vm.expectRevert(VaultUSDC.VaultUSDC__InvalidReceiver.selector);
        vault.deposit(INITIAL_BALANCE, address(0));
        vm.stopPrank();
    }

    function testDepositSuccess() public {
        uint256 depositAmount = 100_000e6;
        uint256 expectedFee = (depositAmount * 200) / 10000; // 2% = 2,000 USDC
        uint256 expectedAfterFee = depositAmount - expectedFee; // 98,000 USDC
        
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        
        uint256 sharesMinted = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Check shares minted (should equal assetsAfterFee na początku)
        assertEq(sharesMinted, expectedAfterFee);
        assertEq(vault.balanceOf(user), expectedAfterFee);
        
        // Check tracking variables
        assertEq(vault.totalDeposited(), expectedAfterFee);
        assertEq(vault.userCostBasis(user), expectedAfterFee);
        assertEq(vault.totalUsers(), 1);
        assertEq(vault.userFirstDepositTime(user), block.timestamp);
        
        // Check fee went to owner
        assertEq(usdc.balanceOf(owner), INITIAL_BALANCE + expectedFee);
        
        // Check totalAssets (vault + strategy)
        // 85% should go to strategy, 15% stay in vault
        uint256 expectedInStrategy = (expectedAfterFee * 8500) / 10000; // 85%
        uint256 expectedInVault = expectedAfterFee - expectedInStrategy; // 15%
        
        assertApproxEqAbs(vault.totalAssets(), expectedAfterFee, 1); // może być +/-1 wei z zaokrągleniami
    }

    function testDepositEmitsEvent() public {
        uint256 depositAmount = 100_000e6;
        uint256 expectedFee = 2_000e6;
        uint256 expectedShares = 98_000e6;
        
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit DepositExecuted(
            user,
            user,
            depositAmount,
            expectedShares,
            expectedFee,
            block.timestamp
        );

        vault.deposit(depositAmount, user);
        vm.stopPrank();
    }

    function testMultipleDeposits() public {
        // First deposit
        vm.startPrank(user);
        usdc.approve(address(vault), 200_000e6);
        vault.deposit(100_000e6, user);
        
        uint256 firstCostBasis = vault.userCostBasis(user);
        assertEq(firstCostBasis, 98_000e6);
        
        // Second deposit
        vault.deposit(100_000e6, user);
        
        uint256 secondCostBasis = vault.userCostBasis(user);
        assertEq(secondCostBasis, 98_000e6 + 98_000e6); // costBasis sumuje się
        assertEq(vault.totalUsers(), 1); // nadal 1 user
        vm.stopPrank();
    }

    function testWithdrawRevertExceedsLimit() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE, user);
        
        vm.expectRevert(VaultUSDC.VaultUSDC__WithdrawExceedsLimit.selector);
        vault.withdraw(200_000e6, user, user); // Max is 100k
        vm.stopPrank();
    }

    function testWithdrawRevertZeroAmount() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE, user);
        
        vm.expectRevert(VaultUSDC.VaultUSDC__ZeroAmount.selector);
        vault.withdraw(0, user, user);
        vm.stopPrank();
    }

    function testWithdrawSuccess() public {
        uint256 depositAmount = 200_000e6;
        uint256 withdrawAmount = 50_000e6;
        
        // Deposit first
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        
        uint256 sharesBefore = vault.balanceOf(user);
        uint256 totalDepositedBefore = vault.totalDeposited();
        
        // Withdraw
        uint256 sharesBurned = vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();
        
        // Check shares burned
        assertEq(vault.balanceOf(user), sharesBefore - sharesBurned);
        
        // Check totalDeposited decreased
        assertEq(vault.totalDeposited(), totalDepositedBefore - withdrawAmount);
        
        // Check user received USDC
        // User miał: 1M initial - 200k deposit + 50k withdraw = 850k
        assertEq(usdc.balanceOf(user), INITIAL_BALANCE - depositAmount + withdrawAmount);
        
        // Check userTotalWithdrawn tracking
        assertEq(vault.userTotalWithdrawn(user), withdrawAmount);
    }
    function testWithdrawWhenTotalDepositedIsLess() public {
    uint256 depositAmount = 100_000e6;
    
   
    vm.startPrank(user);
    usdc.approve(address(vault), depositAmount);
    vault.deposit(depositAmount, user);
    vm.stopPrank();
    
  
    uint256 totalDepositedBefore = vault.totalDeposited();
    
 
    deal(address(usdc), address(vault), 200_000e6);
    
  
    uint256 withdrawAmount = 99_000e6; 
    
    vm.startPrank(user);
    vault.withdraw(withdrawAmount, user, user);
    vm.stopPrank();
    
    
    assertEq(vault.totalDeposited(), 0, "totalDeposited should be 0");
    }
    function testWithdrawEmitsEvent() public {
        uint256 depositAmount = 200_000e6;
        uint256 withdrawAmount = 50_000e6;
        
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        
        // Calculate expected shares burned
        uint256 expectedSharesBurned = vault.previewWithdraw(withdrawAmount);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalExecuted(
            user,
            user,
            user,
            withdrawAmount,
            expectedSharesBurned,
            block.timestamp
        );

        vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();
    }

    function testWithdrawFromStrategy() public {
        uint256 depositAmount = 200_000e6;
        
        // Deposit (85% goes to strategy)
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        
        uint256 vaultBalance = usdc.balanceOf(address(vault));
        
        // Try to withdraw more than vault has (should pull from strategy)
        uint256 withdrawAmount = vaultBalance + 10_000e6;
        
        vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();
        
        // Should succeed because strategy has funds
        assertEq(vault.userTotalWithdrawn(user), withdrawAmount);
    }

    function testWithdrawProfit() public {
        uint256 depositAmount = 100_000e6;
        uint256 expectedAfterFee = 98_000e6;
        
        // Deposit
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Simulate yield (mock strategy gives profit)
        uint256 profit = 5_000e6;
        usdc.mint(address(strategy), profit);
        
        // Now user's shares are worth more
        uint256 userValue = vault.convertToAssets(vault.balanceOf(user));
        
        // withdrawProfit should only withdraw the profit
        vm.startPrank(user);
        uint256 profitWithdrawn = vault.withdrawProfit(user);
        vm.stopPrank();
        
        // Check profit withdrawn
        assertGt(profitWithdrawn, 0);
        
        // Cost basis should remain (minus proportional amount)
        assertLt(vault.userCostBasis(user), expectedAfterFee);
        assertGt(vault.userCostBasis(user), 0);
    }

    function testWithdrawProfitNoProfit() public {
        uint256 depositAmount = 100_000e6;
        
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        
        // No yield, withdrawProfit should return 0
        uint256 profitWithdrawn = vault.withdrawProfit(user);
        assertEq(profitWithdrawn, 0);
        vm.stopPrank();
    }

    function testCostBasisTracking() public {
        uint256 depositAmount = 100_000e6;
        uint256 expectedAfterFee = 98_000e6;
        
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        
        // Initial cost basis
        assertEq(vault.userCostBasis(user), expectedAfterFee);
        
        // Withdraw half
        vault.withdraw(49_000e6, user, user);
        
        // Cost basis should be reduced proportionally
        // Burned ~50% shares → cost basis should be ~50% of original
        assertApproxEqRel(vault.userCostBasis(user), expectedAfterFee / 2, 0.01e18); // 1% tolerance
        
        // Withdraw all remaining
        uint256 remaining = vault.convertToAssets(vault.balanceOf(user));
        vault.withdraw(remaining, user, user);
        
        // Cost basis should be 0
        assertEq(vault.userCostBasis(user), 0);
        vm.stopPrank();
    }

    function testPauseUnpause() public {
        // Pause
        vm.prank(owner);
        vault.pause();
        
        // Deposit should revert
        vm.startPrank(user);
        usdc.approve(address(vault), 100_000e6);
        vm.expectRevert();
        vault.deposit(100_000e6, user);
        vm.stopPrank();
        
        // Unpause
        vm.prank(owner);
        vault.unpause();
        
        // Now should work
        vm.startPrank(user);
        vault.deposit(100_000e6, user);
        vm.stopPrank();
    }

    function testSetStrategy() public {
        MockStrategy newStrategy = new MockStrategy(address(usdc), address(vault));
        
        vm.prank(owner);
        vault.setStrategy(address(newStrategy));
        
        assertEq(vault.strategy(), address(newStrategy));
    }

    function testSetStrategyAdrressRevert() public {
    vm.prank(owner);
    vm.expectRevert(VaultUSDC.VaultUSDC__NoStrategySet.selector);
    vault.setStrategy(address(0));
    }

    function testRebalanceRevertsNoStrategy() public {
    vm.prank(owner);
    VaultUSDC vaultNoStrat = new VaultUSDC(usdc);
    vm.expectRevert(VaultUSDC.VaultUSDC__NoStrategySet.selector);
    vaultNoStrat._rebalanceToStrategy();
    }



    function testRebalanceRevertsNoAssets() public {
    vm.startPrank(user);
    usdc.approve(address(vault), INITIAL_BALANCE);
    vm.expectRevert(VaultUSDC.VaultUSDC__NoShares.selector);
    vault._rebalanceToStrategy();
    }


    function testWithdrawWithAllowance() public {
    uint256 depositAmount = 200_000e6;
    uint256 withdrawAmount = 50_000e6;
    
  
    vm.startPrank(user);
    usdc.approve(address(vault), depositAmount);
    vault.deposit(depositAmount, user);
    vm.stopPrank();
    
  
    address spender = owner;
    uint256 sharesToApprove = vault.previewWithdraw(withdrawAmount);
    
    vm.prank(user);
    vault.approve(spender, sharesToApprove);
    
    
    assertEq(vault.allowance(user, spender), sharesToApprove);
    
    
    uint256 ownerBalanceBefore = usdc.balanceOf(owner);
    
    
    vm.prank(spender);
    vault.withdraw(withdrawAmount, spender, user);
    
    
    assertEq(vault.allowance(user, spender), 0);
    
 
    assertEq(usdc.balanceOf(owner), ownerBalanceBefore + withdrawAmount);
    
 
    uint256 expectedRemainingShares = 196_000e6 - sharesToApprove;
    assertEq(vault.balanceOf(user), expectedRemainingShares);
    }

    function testWithdrawFromStrategyReverts() public {
    vm.prank(owner);
    vault.clearStrategy();
    
    uint256 withdrawAmount = 1000;
    
    vm.expectRevert(VaultUSDC.VaultUSDC__NoStrategySet.selector);
    vault._withdrawFromStrategy(withdrawAmount);
    }


    function testWithdrawFromStrategyRevertsInsufficientStrategyLiquidity() public {
    // 1. Setup - user deposituje do vault
    vm.startPrank(user);
    usdc.approve(address(vault), INITIAL_BALANCE);
    vault.deposit(INITIAL_BALANCE, user);
    vm.stopPrank();
    
    // 2. Owner ustawia strategię
    MockStrategy newStrategy = new MockStrategy(address(usdc), address(vault));
    vm.prank(owner);
    vault.setStrategy(address(newStrategy));
    
    // 3. Vault wysyła część środków do strategii
    vm.prank(owner);
    vault.rebalance(); // to wyśle środki do strategii
    
    // 4. Mock zwraca MNIEJ niż requested
    uint256 requestedAmount = 1_000_000e6;
    uint256 returnedAmount = 100e6; // za mało!
    
    vm.mockCall(
        address(newStrategy),
        abi.encodeWithSelector(IStrategy.withdraw.selector, requestedAmount),
        abi.encode(returnedAmount)
    );
    
    // 5. Oczekuj revert InsufficientStrategyLiquidity
    vm.expectRevert(VaultUSDC.VaultUSDC__InsufficientStrategyLiquidity.selector);
    vault._withdrawFromStrategy(requestedAmount);
    }

    function testCheckAndRebalanceRevertsNoStrategy() public {
        vm.prank(owner);
        VaultUSDC vaultNoStrat = new VaultUSDC(usdc);
        vm.expectRevert(VaultUSDC.VaultUSDC__NoStrategySet.selector);
        vaultNoStrat._checkAndRebalanceFromStrategy();
    }

    function testWithdrawProfitRevertsNoShares() public {
        vm.prank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vm.expectRevert(VaultUSDC.VaultUSDC__NoShares.selector);
        vault.withdrawProfit(user);
    }
    function testUpdateTargetLiquiditySuccess() public {
        uint256 oldTarget = vault.targetLiquidityBPS(); // 1500 (default)
        uint256 newTarget = 2000;
        
        
        vm.prank(owner);
        vault.updateTargetLiquidity(newTarget);
        
        assertEq(vault.targetLiquidityBPS(), newTarget);
    }

    function testUpdateTargetLiquidityRevertsTooHigh() public {
        vm.prank(owner);
        vm.expectRevert("Max 50%");
        vault.updateTargetLiquidity(5001);
    }

    function testUpdateTargetLiquidityRevertsTooLow() public {
        vm.prank(owner);
        vm.expectRevert("Min 5%");
        vault.updateTargetLiquidity(499);
    }

    function testUpdateTargetLiquidityRevertsNotOwner() public {
        vm.prank(user);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        vault.updateTargetLiquidity(2000);
    }

    function testEmergencyWithdraw() public {
    vm.startPrank(owner); // ✅ Owner od samego początku
    
    // Wszystko jako owner
    MockStrategy newStrategy = new MockStrategy(address(usdc), address(vault));
    vault.setStrategy(address(newStrategy));
    usdc.approve(address(vault), INITIAL_BALANCE);
    vault.deposit(INITIAL_BALANCE, owner);
    vault.rebalance();
    vault.pause();
    vault.emergencyWithdrawFromStrategy();
    
    vm.stopPrank();
    
    uint256 vaultBalance = usdc.balanceOf(address(vault));
    assertGt(vaultBalance, 0, "Vault should have funds after emergency withdraw");
    }

    function testGetUserBalance() public {
        uint256 amountToDeposit = 1000;
        uint256 expectedAmountAfterFees = 980;
        vm.startPrank(user);
        usdc.approve(address(vault), amountToDeposit);
        vault.deposit(amountToDeposit, user);
        vm.stopPrank();
        assertEq(vault.getUserBalance(user), expectedAmountAfterFees);
    }
}