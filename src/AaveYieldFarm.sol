// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IAaveLendingPool} from "../interfaces/AaveLedningPool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";





contract AaveYieldFarm is IStrategy {

    error AaveYieldFarm__ZeroDeposit();
    error AaveYieldFarm__ZeroAmountToWithdraw();



    event Deposited(uint256 amount, uint256 timestamp);


    // TODO: Add Aave Yield Farm Contract
    using SafeERC20 for IERC20;
    IERC20 public immutable override asset; // USDC
    IAaveLendingPool public immutable lendingPool;
    address public vault;
    IERC20 public aToken; // aUSDC
    bool public active;

    modifier ownable

    constructor(address _asset, address _lendingPool, address _aToken, address _vault) Ownable() {
        asset = IERC20(_asset);
        lendingPool = IAaveLendingPool(_lendingPool);
        aToken = IERC20(_aToken);
        vault = _vault;
        active = true;

        asset.approve(_lendingPool, type(uint256).max);

    }


    function deposit(uint256 amount) external override {
        if(amount == 0) revert AaveYieldFarm__ZeroDeposit();

        asset.safeTransferFrom(vault, address(this), amount);

        lendingPool.deposit(address(asset), amount, address(this), 0);

        emit Deposited(amount, block.timestamp);
    }

    function withdraw(uint256)external override{
        if(amount == 0) revert AaveYieldFarm__ZeroAmountToWithdraw();

        uint256 aTokenBalance = aToken.balanceOf(address(this));
        lendingPool.withdraw(address(asset), aTokenBalance, vault);
        
    }







    function harvest(){}
    function balanceOf() external view returns (uint256){}
    function asset() external view returns (address){}
    function isActive() external view returns (bool){}
    function emergencyWithdraw(){}


}
