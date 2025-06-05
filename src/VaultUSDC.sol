// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

interface IStragety{
    function despoit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function totalAssets() external view returns(uint256);
    function harvest()external returns(uint256);
    }





contract VaultUSDC is ERC4626, Pausable, Ownable, ReentrancyGuard {

    using SafeTransferLib for ERC20;


    // ============ STATE VARIABLES ============ \\
    IStragety public strategy;
    uint256 public depositLimit;
    uint256 public withdrawLimit;
    uint256 public managmentFee; //basic points (100 = 1%)
    uint256 public lastHarvest;
    uint256 public totalDeposited;
    

    uint256 public idleCashRatio = 1000; //10%



    constructor(ERC20 _asset) ERC4626(_asset) ERC20("VaultUSDC", "VUSDC") Ownable(msg.sender) {
        managmentFee = 200; 
        depositLimit = 1000000e6;
        withdrawLimit = 100000e6;
        lastHarvest = block.timestamp;
    }



    



    


    // constructor() {
    //     //USDC sepolia testnet address
    //     token = IERC20(0x8267cF9254734C6Eb452a7bb9AAF97B392258b21);
    // }
   
}