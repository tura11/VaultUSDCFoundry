// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract VaultUSDC is ERC4626, Ownable, Pausable, ReentrancyGuard {

    using SafeERC20 for IERC20;


    error VaultUSDC__ExceededMaxDeposit();
    error VaultUSDC__ExceededMaxWithdraw();

    event deposited(address sender, uint256 assets, uint256 shares);
    event withdrawed(address sender, uint256 assets, uint256 shares);



    uint256 public  maxDeposit;
    uint256 public  maxWithdraw;
    uint256 public  managmentFee;
    uint256 public  totalDeposited;

    

    constructor(ERC20 _asset) ERC4626(_asset) ERC20("VaultUSDC", "USDC") Ownable(msg.sender){
        maxDeposit = 1000000e6;
        maxWithdraw = 100000e6;
        managmentFee = 2;//2%
        totalDeposited = 0;
    }

    function deposit(uint256 assets, address receiver) public override  nonReentrant whenNotPaused returns (uint256){
        if(assets > maxDeposit) revert VaultUSDC__ExceededMaxDeposit();
        uint256 assetsFee = (assets * managmentFee) / 100;
        uint256 assetesAfterFee = assets - assetsFee;
        if(assetsFee > 0){
            IERC20(asset()).safeTransferFrom(msg.sender, owner(), assetsFee);
        }
        uint256 shares = super.deposit(assetesAfterFee, receiver);
        totalDeposited += assetesAfterFee;
        emit deposited(msg.sender, assets, shares);
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant whenNotPaused returns (uint256){
        if(assets > maxWithdraw) revert VaultUSDC__ExceededMaxWithdraw();
        uint256 shares = super.withdraw(assets, receiver, owner);
        totalDeposited -= assets;
        emit withdrawed(msg.sender, assets, shares);
        return shares;
    }



}