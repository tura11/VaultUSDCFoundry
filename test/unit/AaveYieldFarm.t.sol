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
}