// // SPDX-License-Identifier: MIT

// pragma solidity 0.8.24;

// import {Test, console} from "forge-std/Test.sol";
// import {VaultUSDC} from "../../src/VaultUSDC.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


// contract testVaultUSDC is Test {

//     event deposited(address indexed sender, uint256 assets, uint256 shares);
//     event withdrawed(address indexed sender, uint256 assets, uint256 shares);


//     ERC20Mock usdc;
//     VaultUSDC vault;
//     address user;
//     address owner;
//     uint256 public constant INITIAL_BALANCE = 1000000e6;


//     function setUp() public {
//         user = makeAddr("user");
//         owner = makeAddr("owner");

//         usdc = new ERC20Mock();
//         usdc.mint(user, INITIAL_BALANCE);

//         vm.startPrank(owner);
//         vault = new VaultUSDC(usdc);
//         vm.stopPrank();

//     }

//     function testConstructor() public {
//         assertEq(vault.name(), "VaultUSDC");
//         assertEq(vault.symbol(), "USDC");
//         assertEq(vault.maxDeposit(), 1000000e6);
//         assertEq(vault.maxWithdraw(), 100000e6);
//         assertEq(vault.managmentFee(), 2);
//         assertEq(vault.totalDeposited(), 0);
//     }


//     function testDepositRevert() public {
//         vm.startPrank(user);
//         vm.expectRevert(VaultUSDC.VaultUSDC__ExceededMaxDeposit.selector);
//         vault.deposit(10000000e6, msg.sender);
//         vm.stopPrank();
//     }

//    function testAssetsAfterFee_CheckIncrement() public {
//         uint256 assets = 1000000e6;
//         uint256 expectedAssetsAfterFee = 980000e6;
        
//         uint256 totalDepositedBefore = vault.totalDeposited();
        
//         vm.startPrank(user);
//         usdc.approve(address(vault), assets);
//         vault.deposit(assets, user);
//         vm.stopPrank();
        
//         uint256 totalDepositedAfter = vault.totalDeposited();
//         uint256 actualIncrement = totalDepositedAfter - totalDepositedBefore;
        
//         assertEq(actualIncrement, expectedAssetsAfterFee, "Assets after fee should match increment");
//     }

//     function testDepositEmitEvent() public {
//     vm.startPrank(user);
//     usdc.approve(address(vault), INITIAL_BALANCE);

//     uint256 fee = (INITIAL_BALANCE * vault.managmentFee()) / 100;
//     uint256 shares = INITIAL_BALANCE - fee;

//     vm.expectEmit(true, false, false, true);
//     emit deposited(user, INITIAL_BALANCE, shares);

//     vault.deposit(INITIAL_BALANCE, user);
//     vm.stopPrank();
//     }

//     function testTotalDepositIsUpdated() public {
//         uint256 fee = (INITIAL_BALANCE * vault.managmentFee()) / 100;
//         uint256 expectedTotalDeposit = INITIAL_BALANCE - fee;
//         vm.startPrank(user);
//         usdc.approve(address(vault), INITIAL_BALANCE);
//         vault.deposit(INITIAL_BALANCE, user);
//         uint256 totalDepositAfter = vault.totalDeposited();
//         vm.stopPrank();
//         assertEq(expectedTotalDeposit, totalDepositAfter);
//     }

//     function testWithdrawRevert() public {
//         vm.startPrank(user);
//         vm.expectRevert(VaultUSDC.VaultUSDC__ExceededMaxWithdraw.selector);
//         vault.withdraw(10000000e6, msg.sender, msg.sender);
//         vm.stopPrank();
//     }

//     function testTotalDepositIsUpdatedWhenWithdraw() public {
//         uint256 expectedTotalDepositAfterWithdraw = 880000e6;
//         vm.startPrank(user);
//         usdc.approve(address(vault), INITIAL_BALANCE);
//         vault.deposit(INITIAL_BALANCE, user);
//         vault.withdraw(100000e6, user, user);
//         uint256 totalDepositAfterWithdraw = vault.totalDeposited();
//         vm.stopPrank();
//         assertEq(expectedTotalDepositAfterWithdraw, totalDepositAfterWithdraw);
//     }


//     function testWithdrawEmitEvent() public {
//     uint256 amount = 100_000e6; 
//     vm.startPrank(user);
//     usdc.approve(address(vault), INITIAL_BALANCE); 

//     vault.deposit(INITIAL_BALANCE, user); 


//     uint256 sharesToWithdraw = amount;

//     vm.expectEmit(true, false, false, true);
//     emit withdrawed(user, amount, sharesToWithdraw);
//     vault.withdraw(amount, user, user);
//     vm.stopPrank();
// }


    








// }

