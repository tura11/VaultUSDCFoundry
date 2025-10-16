// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VaultUSDC} from "../../src/VaultUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockStrategy} from "../mocks/AaveStrategyMock.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";

/**
 * @title testVaultUSDC
 * @notice Comprehensive NatSpec-style unit test suite for the VaultUSDC contract.
 * @dev This test contract is organized into logical sections: setup, deposit tests,
 *      withdrawal tests, strategy/rebalance tests, profit & cost-basis tests,
 *      access control & parameter updates, emergency flows and utility/view tests.
 *
 *      Each test contains a short @notice describing the purpose and a @dev note
 *      explaining the steps taken during the test. The tests use Forge's `vm` helpers
 *      and the ERC20Mock / MockStrategy to simulate token transfers and strategy behavior.
 */
contract testVaultUSDC is Test {
    // ---------------------------
    // Events (mirrors production events for emit assertions)
    // ---------------------------

    /// @notice Emitted when a deposit is executed (test-only replica for expectEmit checks).
    event DepositExecuted(
        address indexed user,
        address indexed receiver,
        uint256 assetsDeposited,
        uint256 sharesReceived,
        uint256 managementFeeCharged,
        uint256 timestamp
    );

    /// @notice Emitted when a withdrawal is executed (test-only replica for expectEmit checks).
    event WithdrawalExecuted(
        address indexed user,
        address indexed receiver,
        address indexed shareOwner,
        uint256 assetsWithdrawn,
        uint256 sharesBurned,
        uint256 timestamp
    );

    /// @notice Emitted when vault parameters are updated (test-only replica for expectEmit checks).
    event VaultParametersUpdated(
        uint256 oldMaxDeposit,
        uint256 newMaxDeposit,
        uint256 oldMaxWithdraw,
        uint256 newMaxWithdraw,
        uint256 oldManagementFee,
        uint256 newManagementFee
    );
    
    /// @notice Emitted for emergency actions (PAUSED / UNPAUSED / EMERGENCY_WITHDRAW) (test-only)
    event EmergencyAction(
        string actionType,
        address indexed admin,
        uint256 timestamp
    );

    // ---------------------------
    // Test state variables
    // ---------------------------
    MockStrategy strategy;
    ERC20Mock usdc;
    VaultUSDC vault;
    address user;
    address owner;

    /// @notice Initial per-account mock USDC balance used in tests (6 decimals assumed)
    uint256 public constant INITIAL_BALANCE = 1_000_000e6;

    // ---------------------------
    // Setup
    // ---------------------------

    /**
     * @notice Deploy mocks and initialize vault and strategy for each test.
     * @dev Deploys ERC20Mock and mints INITIAL_BALANCE to both user and owner.
     *      Deploys VaultUSDC as owner, deploys MockStrategy and assigns it to vault.
     */
    function setUp() public {
        user = makeAddr("user");
        owner = makeAddr("owner");

        // Deploy mock USDC token. ERC20Mock uses 18 decimals by default in OpenZeppelin mock,
        // but tests and VaultUSDC assume 6 decimals semantics. The mock is used only for transfer semantics.
        usdc = new ERC20Mock();

        // Seed balances for owner and user
        usdc.mint(owner, INITIAL_BALANCE);
        usdc.mint(user, INITIAL_BALANCE);

        // Deploy vault as owner
        vm.startPrank(owner);
        vault = new VaultUSDC(usdc);
        vm.stopPrank();

        // Deploy mock strategy and set it on the vault
        strategy = new MockStrategy(address(usdc), address(vault));
        vm.prank(owner);
        vault.setStrategy(address(strategy));
    }

    // ---------------------------
    // Constructor / initial state tests
    // ---------------------------

    /**
     * @notice Verifies VaultUSDC constructor initializes expected metadata and limits.
     * @dev Uses view assertions to validate name, symbol, deposit/withdraw limits, management fee,
     *      and zeroed tracking variables.
     */
    function testConstructor() public view {
        assertEq(vault.name(), "VaultUSDC");
        assertEq(vault.symbol(), "vUSDC");
        assertEq(vault.maxDepositLimit(), 1_000_000e6);
        assertEq(vault.maxWithdrawLimit(), 100_000e6);
        assertEq(vault.managementFee(), 200); // 2%
        assertEq(vault.totalDeposited(), 0);
        assertEq(vault.totalUsers(), 0);
    }

    // ---------------------------
    // Deposit tests
    // ---------------------------

    /**
     * @notice deposit should revert when amount exceeds vault max deposit limit.
     * @dev Approves large allowance then calls deposit expecting VaultUSDC__DepositExceedsLimit.
     */
    function testDepositRevertExceedsLimit() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 10_000_000e6);

        vm.expectRevert(VaultUSDC.VaultUSDC__DepositExceedsLimit.selector);
        vault.deposit(10_000_000e6, user);
        vm.stopPrank();
    }

    /**
     * @notice deposit should revert when amount is zero.
     * @dev Approves allowance then calls deposit(0) expecting VaultUSDC__ZeroAmount.
     */
    function testDepositRevertZeroAmount() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);

        vm.expectRevert(VaultUSDC.VaultUSDC__ZeroAmount.selector);
        vault.deposit(0, user);
        vm.stopPrank();
    }

    /**
     * @notice deposit should revert when receiver is zero address.
     * @dev Approves allowance then calls deposit with address(0) expecting VaultUSDC__InvalidReceiver.
     */
    function testDepositRevertInvalidAddress() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);

        vm.expectRevert(VaultUSDC.VaultUSDC__InvalidReceiver.selector);
        vault.deposit(INITIAL_BALANCE, address(0));
        vm.stopPrank();
    }

    /**
     * @notice Successful deposit updates balances, mints shares correctly and forwards fee to owner.
     * @dev Deposits 100k USDC, asserts fee deduction, shares minted equal assets after fee,
     *      and tracking variables (totalDeposited, userCostBasis, totalUsers, firstDepositTime).
     */
    function testDepositSuccess() public {
        uint256 depositAmount = 100_000e6;
        uint256 expectedFee = (depositAmount * 200) / 10000; // 2%
        uint256 expectedAfterFee = depositAmount - expectedFee;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);

        uint256 sharesMinted = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Shares minted should equal assets after fee at initial deposit
        assertEq(sharesMinted, expectedAfterFee);
        assertEq(vault.balanceOf(user), expectedAfterFee);

        // Tracking variables
        assertEq(vault.totalDeposited(), expectedAfterFee);
        assertEq(vault.userCostBasis(user), expectedAfterFee);
        assertEq(vault.totalUsers(), 1);
        assertEq(vault.userFirstDepositTime(user), block.timestamp);

        // Fee forwarded to owner
        assertEq(usdc.balanceOf(owner), INITIAL_BALANCE + expectedFee);

        // totalAssets should approximately equal expectedAfterFee (vault + strategy)
        assertApproxEqAbs(vault.totalAssets(), expectedAfterFee, 1);
    }

    /**
     * @notice Deposit should emit DepositExecuted event with correct parameters.
     * @dev Uses vm.expectEmit and emits a replica DepositExecuted event before calling deposit.
     */
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

    /**
     * @notice Multiple deposits by same user should accumulate cost basis and not increment user count.
     * @dev Performs two deposits and asserts cost basis sums and totalUsers remains 1.
     */
    function testMultipleDeposits() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 200_000e6);
        vault.deposit(100_000e6, user);

        uint256 firstCostBasis = vault.userCostBasis(user);
        assertEq(firstCostBasis, 98_000e6);

        // Second deposit
        vault.deposit(100_000e6, user);

        uint256 secondCostBasis = vault.userCostBasis(user);
        assertEq(secondCostBasis, 98_000e6 + 98_000e6);
        assertEq(vault.totalUsers(), 1);
        vm.stopPrank();
    }

    // ---------------------------
    // Withdraw tests
    // ---------------------------

    /**
     * @notice Withdraw should revert when requested amount exceeds vault's withdraw limit.
     * @dev Deposit initial balance then attempt to withdraw more than maxWithdrawLimit expecting revert.
     */
    function testWithdrawRevertExceedsLimit() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE, user);

        vm.expectRevert(VaultUSDC.VaultUSDC__WithdrawExceedsLimit.selector);
        vault.withdraw(200_000e6, user, user);
        vm.stopPrank();
    }

    /**
     * @notice Withdraw should revert when amount is zero.
     * @dev Deposit then call withdraw(0) expecting VaultUSDC__ZeroAmount.
     */
    function testWithdrawRevertZeroAmount() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE, user);

        vm.expectRevert(VaultUSDC.VaultUSDC__ZeroAmount.selector);
        vault.withdraw(0, user, user);
        vm.stopPrank();
    }

    /**
     * @notice Successful withdraw burns shares, updates tracking and transfers assets to recipient.
     * @dev Deposit 200k, withdraw 50k and assert balances, totalDeposited and userTotalWithdrawn.
     */
    function testWithdrawSuccess() public {
        uint256 depositAmount = 200_000e6;
        uint256 withdrawAmount = 50_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        uint256 sharesBefore = vault.balanceOf(user);
        uint256 totalDepositedBefore = vault.totalDeposited();

        uint256 sharesBurned = vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();

        // Shares burned
        assertEq(vault.balanceOf(user), sharesBefore - sharesBurned);

        // totalDeposited decreased by withdrawAmount
        assertEq(vault.totalDeposited(), totalDepositedBefore - withdrawAmount);

        // User received USDC
        assertEq(usdc.balanceOf(user), INITIAL_BALANCE - depositAmount + withdrawAmount);

        // Tracking of total withdrawn
        assertEq(vault.userTotalWithdrawn(user), withdrawAmount);
    }

    /**
     * @notice Withdraw when vault holds less on-record than actual token balance should zero totalDeposited.
     * @dev Deposit 100k then artificially increase vault token balance with deal(); withdraw and assert totalDeposited resets to 0.
     */
    function testWithdrawWhenTotalDepositedIsLess() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 totalDepositedBefore = vault.totalDeposited();

        // Force additional tokens into vault address to simulate misalignment
        deal(address(usdc), address(vault), 200_000e6);

        uint256 withdrawAmount = 99_000e6;

        vm.startPrank(user);
        vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();

        assertEq(vault.totalDeposited(), 0, "totalDeposited should be 0");
    }
    /// @notice Revert when caller has no shares (cover VaultUSDC__NoShares branch)
    function testWithdrawProfitRevertsWhenNoSharesCover() public {
        address noHolder = makeAddr("noHolder");

        // Ensure caller has zero shares (do not deposit for noHolder)
        vm.prank(noHolder);
        vm.expectRevert(VaultUSDC.VaultUSDC__NoShares.selector);
        vault.withdrawProfit(noHolder);
    }


    /**
     * @notice Withdraw should emit WithdrawalExecuted with correct parameters.
     * @dev Use vm.expectEmit with a replica event then call withdraw.
     */
    function testWithdrawEmitsEvent() public {
        uint256 depositAmount = 200_000e6;
        uint256 withdrawAmount = 50_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

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

    /**
     * @notice Withdraw that requires pulling funds from the strategy succeeds when strategy has liquidity.
     * @dev Deposit funds, compute withdraw larger than vault balance so vault pulls from strategy.
     */
    function testWithdrawFromStrategy() public {
        uint256 depositAmount = 200_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        uint256 vaultBalance = usdc.balanceOf(address(vault));

        // Withdraw more than immediate vault balance so vault must request from strategy
        uint256 withdrawAmount = vaultBalance + 10_000e6;

        vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();

        // Should have recorded the withdrawal
        assertEq(vault.userTotalWithdrawn(user), withdrawAmount);
    }

    // ---------------------------
    // Profit & Cost-basis tests
    // ---------------------------

    /**
     * @notice When strategy generates profit, user can withdraw profit via withdrawProfit.
     * @dev Mint profit tokens to strategy mock, then call withdrawProfit and assert positive amount and cost-basis adjustment.
     */
    function testWithdrawProfit() public {
        uint256 depositAmount = 100_000e6;
        uint256 expectedAfterFee = 98_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Simulate yield in strategy
        uint256 profit = 5_000e6;
        usdc.mint(address(strategy), profit);

        // User value increases
        uint256 userValue = vault.convertToAssets(vault.balanceOf(user));

        vm.startPrank(user);
        uint256 profitWithdrawn = vault.withdrawProfit(user);
        vm.stopPrank();

        assertGt(profitWithdrawn, 0);
        assertLt(vault.userCostBasis(user), expectedAfterFee);
        assertGt(vault.userCostBasis(user), 0);
    }

    /**
     * @notice withdrawProfit returns zero when no profit exists.
     * @dev Deposit without minting profit then call withdrawProfit expecting zero.
     */
    function testWithdrawProfitNoProfit() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        uint256 profitWithdrawn = vault.withdrawProfit(user);
        assertEq(profitWithdrawn, 0);
        vm.stopPrank();
    }

    /**
     * @notice Cost basis tracking decreases proportionally to withdrawn shares.
     * @dev Deposit, withdraw roughly half and assert cost basis ~50% then withdraw all and assert zero.
     */
    function testCostBasisTracking() public {
        uint256 depositAmount = 100_000e6;
        uint256 expectedAfterFee = 98_000e6;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        // Initial cost basis set
        assertEq(vault.userCostBasis(user), expectedAfterFee);

        // Withdraw half
        vault.withdraw(49_000e6, user, user);

        // Cost basis reduced proportionally with 1% tolerance
        assertApproxEqRel(vault.userCostBasis(user), expectedAfterFee / 2, 0.01e18);

        // Withdraw remaining
        uint256 remaining = vault.convertToAssets(vault.balanceOf(user));
        vault.withdraw(remaining, user, user);

        assertEq(vault.userCostBasis(user), 0);
        vm.stopPrank();
    }

    // ---------------------------
    // Strategy & rebalance tests
    // ---------------------------

    /**
     * @notice Rebalance to strategy should revert if no strategy is set.
     * @dev Instantiate a fresh VaultUSDC and call internal rebalance expecting NoStrategySet.
     */
    function testRebalanceRevertsNoStrategy() public {
        vm.prank(owner);
        VaultUSDC vaultNoStrat = new VaultUSDC(usdc);
        vm.expectRevert(VaultUSDC.VaultUSDC__NoStrategySet.selector);
        vaultNoStrat._rebalanceToStrategy();
    }

    /**
     * @notice Rebalance should revert when there are no shares (no assets to rebalance).
     * @dev Approve an allowance but do not deposit; calling _rebalanceToStrategy should revert with NoShares.
     */
    function testRebalanceRevertsNoAssets() public {
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vm.expectRevert(VaultUSDC.VaultUSDC__NoShares.selector);
        vault._rebalanceToStrategy();
    }

    /**
     * @notice _withdrawFromStrategy should revert when no strategy set.
     * @dev Clear strategy and call _withdrawFromStrategy expecting NoStrategySet.
     */
    function testWithdrawFromStrategyReverts() public {
        vm.prank(owner);
        vault.clearStrategy();

        uint256 withdrawAmount = 1000;

        vm.expectRevert(VaultUSDC.VaultUSDC__NoStrategySet.selector);
        vault._withdrawFromStrategy(withdrawAmount);
    }

    /**
     * @notice _withdrawFromStrategy should revert when strategy returns less than requested.
     * @dev Deposit funds, set a new strategy, rebalance (send funds), then mock IStrategy.withdraw to return less than requested and expect revert.
     */
    function testWithdrawFromStrategyRevertsInsufficientStrategyLiquidity() public {
        // 1. User deposits to vault
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE, user);
        vm.stopPrank();

        // 2. Owner sets a new strategy and rebalances
        MockStrategy newStrategy = new MockStrategy(address(usdc), address(vault));
        vm.prank(owner);
        vault.setStrategy(address(newStrategy));

        vm.prank(owner);
        vault.rebalance(); // send funds to strategy

        // 3. Mock strategy.withdraw to return insufficient amount
        uint256 requestedAmount = 1_000_000e6;
        uint256 returnedAmount = 100e6;

        vm.mockCall(
            address(newStrategy),
            abi.encodeWithSelector(IStrategy.withdraw.selector, requestedAmount),
            abi.encode(returnedAmount)
        );

        vm.expectRevert(VaultUSDC.VaultUSDC__InsufficientStrategyLiquidity.selector);
        vault._withdrawFromStrategy(requestedAmount);
    }

    /**
     * @notice _checkAndRebalanceFromStrategy should revert when no strategy is set.
     * @dev Instantiates a fresh VaultUSDC without a strategy and expects NoStrategySet on checkAndRebalance.
     */
    function testCheckAndRebalanceRevertsNoStrategy() public {
        vm.prank(owner);
        VaultUSDC vaultNoStrat = new VaultUSDC(usdc);
        vm.expectRevert(VaultUSDC.VaultUSDC__NoStrategySet.selector);
        vaultNoStrat._checkAndRebalanceFromStrategy();
    }

    // ---------------------------
    // Allowance & delegated withdraw tests
    // ---------------------------

    /**
     * @notice Allows a spender to withdraw on behalf of user and ensures allowance is cleared after withdraw.
     * @dev User approves vault share allowance, owner acts as spender and withdraws to owner address.
     */
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

        // Allowance cleared after spender withdraws
        assertEq(vault.allowance(user, spender), 0);

        // Owner received assets
        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + withdrawAmount);

        uint256 expectedRemainingShares = 196_000e6 - sharesToApprove; // derived from earlier assumptions
        assertEq(vault.balanceOf(user), expectedRemainingShares);
    }

    // ---------------------------
    // Access control & pause/unpause tests
    // ---------------------------

    /**
     * @notice Pause the vault and ensure deposit reverts while paused; unpause and ensure normal operation.
     * @dev Uses owner to pause/unpause and a user to attempt deposits while paused and after unpause.
     */
    function testPauseUnpause() public {
        // Pause the vault
        vm.prank(owner);
        vault.pause();

        // Deposit should revert while paused
        vm.startPrank(user);
        usdc.approve(address(vault), 100_000e6);
        vm.expectRevert();
        vault.deposit(100_000e6, user);
        vm.stopPrank();

        // Unpause the vault
        vm.prank(owner);
        vault.unpause();

        // Deposit should now succeed
        vm.startPrank(user);
        vault.deposit(100_000e6, user);
        vm.stopPrank();
    }

    /**
     * @notice Setting a strategy address should update the vault strategy pointer.
     * @dev Deploy a new MockStrategy, set it as strategy and assert vault.strategy() equals its address.
     */
    function testSetStrategy() public {
        MockStrategy newStrategy = new MockStrategy(address(usdc), address(vault));

        vm.prank(owner);
        vault.setStrategy(address(newStrategy));

        assertEq(vault.strategy(), address(newStrategy));
    }

    /**
     * @notice Setting strategy to address(0) should revert with NoStrategySet.
     * @dev Owner attempts to set zero strategy and expect revert.
     */
    function testSetStrategyAdrressRevert() public {
        vm.prank(owner);
        vm.expectRevert(VaultUSDC.VaultUSDC__NoStrategySet.selector);
        vault.setStrategy(address(0));
    }

    // ---------------------------
    // Target liquidity update tests
    // ---------------------------

    /**
     * @notice Owner can update target liquidity BPS within allowed bounds.
     * @dev Calls updateTargetLiquidity as owner and asserts new value.
     */
    function testUpdateTargetLiquiditySuccess() public {
        uint256 newTarget = 2000; // 20%

        vm.prank(owner);
        vault.updateTargetLiquidity(newTarget);

        assertEq(vault.targetLiquidityBPS(), newTarget);
    }

    /**
     * @notice updateTargetLiquidity should revert when value too high (>50% represented as 5000 BPS).
     * @dev Expects revert string "Max 50%" when owner calls with 5001.
     */
    function testUpdateTargetLiquidityRevertsTooHigh() public {
        vm.prank(owner);
        vm.expectRevert("Max 50%");
        vault.updateTargetLiquidity(5001);
    }

    /**
     * @notice updateTargetLiquidity should revert when value too low (<5% represented as 500 BPS).
     * @dev Expects revert string "Min 5%" when owner calls with 499.
     */
    function testUpdateTargetLiquidityRevertsTooLow() public {
        vm.prank(owner);
        vm.expectRevert("Min 5%");
        vault.updateTargetLiquidity(499);
    }

    /**
     * @notice Only owner may call updateTargetLiquidity.
     * @dev Non-owner call should revert with an Ownable unauthorized error.
     */
    function testUpdateTargetLiquidityRevertsNotOwner() public {
        vm.prank(user);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        vault.updateTargetLiquidity(2000);
    }

    // ---------------------------
    // Emergency & pause flows
    // ---------------------------

    /**
     * @notice emergencyWithdrawFromStrategy should return funds to vault when invoked by owner in paused state.
     * @dev Owner sets strategy, deposits funds, rebalances, pauses, then calls emergencyWithdrawFromStrategy.
     */
    function testEmergencyWithdraw() public {
        vm.startPrank(owner);

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

    /**
     * @notice emergencyWithdraw should revert when vault is not paused.
     * @dev Call emergencyWithdraw as owner without pausing and expect revert.
     */
    function testEmergencyWithdrawRevertsNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(); // EnforcedPause
        vault.emergencyWithdraw();
    }

    /**
     * @notice emergencyWithdraw (owner) should transfer vault balance to owner when paused.
     * @dev User deposits, owner pauses then calls emergencyWithdraw and verifies funds moved to owner.
     */
    function testEmergencyWithdrawSuccess() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 100000e6);
        vault.deposit(100000e6, user);
        vm.stopPrank();

        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);

        vm.startPrank(owner);
        vault.pause();

        vm.expectEmit(true, true, true, true);
        emit EmergencyAction("EMERGENCY_WITHDRAW", owner, block.timestamp);

        vault.emergencyWithdraw();
        vm.stopPrank();

        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + vaultBalance);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    // ---------------------------
    // Utility & view function tests
    // ---------------------------

    /**
     * @notice getUserBalance should return user's current asset balance converted from shares.
     * @dev Deposit a small amount and assert getUserBalance equals assets after fee.
     */
    function testGetUserBalance() public {
        uint256 amountToDeposit = 1000;
        uint256 expectedAmountAfterFees = 980;
        vm.startPrank(user);
        usdc.approve(address(vault), amountToDeposit);
        vault.deposit(amountToDeposit, user);
        vm.stopPrank();
        assertEq(vault.getUserBalance(user), expectedAmountAfterFees);
    }

    /**
     * @notice getUserInfo returns aggregated user metrics for external consumption.
     * @dev Deposit then withdraw some amount and verify returned tuple matches internal state.
     */
    function testGetUserInfo() public {
        uint256 depositAmount = 1000;
        uint256 withdrawAmount = 100;

        uint256 depositTime = block.timestamp;

        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();

        (
            uint256 totalShares,
            uint256 totalAssets,
            uint256 totalDeposits,
            uint256 totalWithdrawals,
            uint256 firstDepositTime
        ) = vault.getUserInfo(user);

        uint256 expectedShares = 980 - vault.previewWithdraw(withdrawAmount);
        assertEq(totalShares, expectedShares, "Wrong shares");
        assertEq(totalAssets, vault.convertToAssets(totalShares), "Wrong assets");
        assertEq(totalDeposits, 980, "Wrong total deposits");
        assertEq(totalWithdrawals, withdrawAmount, "Wrong total withdrawals");
        assertEq(firstDepositTime, depositTime, "Wrong first deposit time");
    }

    /**
     * @notice getVaultStats should return aggregated vault metrics such as TVL, fees and active users.
     * @dev Deposit initial balance and assert returned stats equal expected values.
     */
    function testGetVaultStats() public {
        uint256 expetctedAmountAfterFees = 980000e6;
        vm.startPrank(user);
        usdc.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(INITIAL_BALANCE, user);
        vm.stopPrank();

        (
            uint256 totalValueLocked,
            uint256 activeUsers,
            uint256 feesCollected,
            uint256 currentMaxDeposit,
            uint256 currentMaxWithdraw,
            uint256 currentManagementFee
        ) = vault.getVaultStats();

        assertEq(currentManagementFee, 200);
        assertEq(currentMaxDeposit, INITIAL_BALANCE);
        assertEq(currentMaxWithdraw, 100000e6);
        assertEq(totalValueLocked, expetctedAmountAfterFees);
        assertEq(activeUsers, 1);
        assertEq(feesCollected, 20000e6);
    }

    /**
     * @notice canDeposit should not revert for valid inputs.
     * @dev This is a read-only view test; calling canDeposit with a sane amount should not revert.
     */
    function testCanDepositSuccess() public view {
        vault.canDeposit(user, 1000e6);
    }

    /**
     * @notice canDeposit should revert when vault is paused.
     * @dev Pause as owner then expect VaultPaused revert when calling canDeposit.
     */
    function testCanDepositRevertsWhenPaused() public {
        vm.prank(owner);
        vault.pause();

        vm.expectRevert(VaultUSDC.VaultUSDC__VaultPaused.selector);
        vault.canDeposit(user, 1000e6);
    }

    /**
     * @notice canDeposit should revert when amount is zero.
     * @dev Expects VaultUSDC__ZeroAmount on zero deposit query.
     */
    function testCanDepositRevertsZeroAmount() public  {
        vm.expectRevert(VaultUSDC.VaultUSDC__ZeroAmount.selector);
        vault.canDeposit(user, 0);
    }

    /**
     * @notice canDeposit should revert when requested deposit exceeds maxDepositLimit.
     * @dev Expects VaultUSDC__DepositExceedsLimit when querying a large amount.
     */
    function testCanDepositRevertsExceedsLimit_View() public  {
        vm.expectRevert(VaultUSDC.VaultUSDC__DepositExceedsLimit.selector);
        vault.canDeposit(user, 2000000e6);
    }

    /**
     * @notice canDeposit should revert when user address is invalid (zero address).
     * @dev Expects VaultUSDC__InvalidUserAddress when passing address(0).
     */
    function testCanDepositRevertsInvalidUser() public  {
        vm.expectRevert(VaultUSDC.VaultUSDC__InvalidUserAddress.selector);
        vault.canDeposit(address(0), 1000e6);
    }

    // ---------------------------
    // canWithdraw tests (view validations)
    // ---------------------------

    /**
     * @notice canWithdraw should succeed for valid user with sufficient balance.
     * @dev Deposit then call canWithdraw expecting no revert.
     */
    function testCanWithdrawSuccess() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 10000e6);
        vault.deposit(10000e6, user);
        vm.stopPrank();

        vault.canWithdraw(user, 1000e6);
    }

    /**
     * @notice canWithdraw should revert when vault is paused.
     * @dev Pause the vault then expect VaultPaused revert when calling canWithdraw.
     */
    function testCanWithdrawRevertsWhenPaused() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 10000e6);
        vault.deposit(10000e6, user);
        vm.stopPrank();

        vm.prank(owner);
        vault.pause();

        vm.expectRevert(VaultUSDC.VaultUSDC__VaultPaused.selector);
        vault.canWithdraw(user, 1000e6);
    }

    /**
     * @notice canWithdraw should revert when amount is zero.
     * @dev Expects VaultUSDC__ZeroAmount revert on zero withdrawal query.
     */
    function testCanWithdrawRevertsZeroAmount() public  {
        vm.expectRevert(VaultUSDC.VaultUSDC__ZeroAmount.selector);
        vault.canWithdraw(user, 0);
    }

    /**
     * @notice canWithdraw should succeed when checking a small withdrawal relative to user's deposit.
     * @dev Deposits small amount and calls canWithdraw with a proportionally small number.
     */
    function testCanWithdrawBelowLimit() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 1e6);
        vault.deposit(1e6, user);
        vm.stopPrank();

        vault.canWithdraw(user, 980_000);
    }

    /**
     * @notice canWithdraw should revert when requested withdrawal exceeds vault's withdraw limit.
     * @dev Deposit large amount then expect WithdrawExceedsLimit revert on very large canWithdraw.
     */
    function testCanWithdrawRevertWithdrawExceedsLimit() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 1000000e6);
        vault.deposit(1000000e6, user);
        vm.stopPrank();

        vm.expectRevert(VaultUSDC.VaultUSDC__WithdrawExceedsLimit.selector);
        vault.canWithdraw(user, 1000000e6);
    }

    /**
     * @notice canWithdraw should revert when user's balance is insufficient.
     * @dev Deposit a small amount then query canWithdraw with a larger amount expecting InsufficientBalance.
     */
    function testCanWithdrawRevertsInsufficientBalance() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();

        vm.expectRevert(VaultUSDC.VaultUSDC__InsufficientBalance.selector);
        vault.canWithdraw(user, 10000e6);
    }

    // ---------------------------
    // Vault parameter update tests
    // ---------------------------

    /**
     * @notice Owner can update vault parameters: maxDeposit, maxWithdraw and management fee.
     * @dev Expect VaultParametersUpdated event and updated state fields after call.
     */
    function testUpdateVaultParametersSuccess() public {
        uint256 newMaxDeposit = 2000000e6;
        uint256 newMaxWithdraw = 200000e6;
        uint256 newFee = 300; // 3%

        vm.expectEmit(true, true, true, true);
        emit VaultParametersUpdated(
            vault.maxDepositLimit(),
            newMaxDeposit,
            vault.maxWithdrawLimit(),
            newMaxWithdraw,
            vault.managementFee(),
            newFee
        );

        vm.prank(owner);
        vault.updateVaultParameters(newMaxDeposit, newMaxWithdraw, newFee);

        assertEq(vault.maxDepositLimit(), newMaxDeposit);
        assertEq(vault.maxWithdrawLimit(), newMaxWithdraw);
        assertEq(vault.managementFee(), newFee);
    }

    /**
     * @notice updateVaultParameters should revert when management fee > 10%.
     * @dev Expect revert string "Fee cannot exceed 10%" when passing 1001 BPS (10.01%).
     */
    function testUpdateVaultParametersRevertsFeeExceeds10Percent() public {
        vm.prank(owner);
        vm.expectRevert("Fee cannot exceed 10%");
        vault.updateVaultParameters(1000000e6, 100000e6, 1001);
    }

    // ---------------------------
    // Pause/unpause combined test (emits emergency events)
    // ---------------------------

    /**
     * @notice Pause and unpause flow should set paused flag and emit emergency events.
     * @dev Expect EmergencyAction events for PAUSED and UNPAUSED and validate deposit behavior during pause.
     */
    function testPauseAndUnpause() public {
        // Expect paused event
        vm.expectEmit(true, true, true, true);
        emit EmergencyAction("PAUSED", owner, block.timestamp);

        vm.prank(owner);
        vault.pause();

        assertTrue(vault.paused());

        vm.startPrank(user);
        usdc.approve(address(vault), 1000e6);
        vm.expectRevert();
        vault.deposit(1000e6, user);
        vm.stopPrank();

        // Expect unpaused event
        vm.expectEmit(true, true, true, true);
        emit EmergencyAction("UNPAUSED", owner, block.timestamp);

        vm.prank(owner);
        vault.unpause();

        assertFalse(vault.paused());

        vm.startPrank(user);
        vault.deposit(1000e6, user);
        vm.stopPrank();
    }

}
