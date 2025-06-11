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

    error VaultUSDC__DepositExceedsLimit();
    error VaultUSDC__WithdrawExceedsLimit();
    error VaultUSDC__ZeroAmount();
    error VaultUSDC__InvalidReceiver();
    error VaultUSDC__InsufficientBalance();
    error VaultUSDC__TransferFailed();
    error VaultUSDC__VaultPaused();
    error VaultUSDC__InvalidUserAddress();

    event DepositExecuted(address indexed user, address indexed receiver, uint256 assetsDeposited, uint256 sharesReceived, uint256 managementFeeCharged, uint256 timestamp);
    event WithdrawalExecuted(address indexed user, address indexed receiver, address indexed shareOwner, uint256 assetsWithdrawn, uint256 sharesBurned, uint256 timestamp);
    event VaultParametersUpdated(uint256 oldMaxDeposit, uint256 newMaxDeposit, uint256 oldMaxWithdraw, uint256 newMaxWithdraw, uint256 oldManagementFee, uint256 newManagementFee);
    event EmergencyAction(string actionType, address indexed admin, uint256 timestamp);

    uint256 public maxDepositLimit;
    uint256 public maxWithdrawLimit;
    uint256 public managementFee;
    uint256 public totalDeposited;
    uint256 public totalFeesCollected;
    uint256 public totalUsers;

    mapping(address => uint256) public userFirstDepositTime;
    mapping(address => uint256) public userTotalDeposited;
    mapping(address => uint256) public userTotalWithdrawn;

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert VaultUSDC__ZeroAmount();
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert VaultUSDC__InvalidReceiver();
        _;
    }

    constructor(ERC20 _asset) ERC4626(_asset) ERC20("VaultUSDC", "vUSDC") Ownable(msg.sender) {
        maxDepositLimit = 1000000e6;
        maxWithdrawLimit = 100000e6;
        managementFee = 200;
        totalDeposited = 0;
        totalFeesCollected = 0;
        totalUsers = 0;
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant whenNotPaused validAmount(assets) validAddress(receiver) returns (uint256) {
        if (assets > maxDepositLimit) {
            revert VaultUSDC__DepositExceedsLimit();
        }

        uint256 assetsFee = (assets * managementFee) / 10000;
        uint256 assetsAfterFee = assets - assetsFee;

        if (assetsFee > 0) {
            IERC20(asset()).safeTransferFrom(msg.sender, owner(), assetsFee);
            totalFeesCollected += assetsFee;
        }

        uint256 shares = super.deposit(assetsAfterFee, receiver);

        if (balanceOf(receiver) == shares) {
            totalUsers++;
            userFirstDepositTime[receiver] = block.timestamp;
        }
        
        totalDeposited += assetsAfterFee;
        userTotalDeposited[receiver] += assets;

        emit DepositExecuted(msg.sender, receiver, assets, shares, assetsFee, block.timestamp);

        return shares;
    }

    function withdraw(uint256 assets, address receiver, address shareOwner) public override nonReentrant whenNotPaused validAmount(assets) validAddress(receiver) returns (uint256) {
        if (assets > maxWithdrawLimit) {
            revert VaultUSDC__WithdrawExceedsLimit();
        }

        uint256 shares = super.withdraw(assets, receiver, shareOwner);

        if (totalDeposited >= assets) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }
        
        userTotalWithdrawn[shareOwner] += assets;

        emit WithdrawalExecuted(msg.sender, receiver, shareOwner, assets, shares, block.timestamp);

        return shares;
    }

    function getUserBalance(address user) public view returns (uint256 shares) {
        return balanceOf(user);
    }

    function getUserInfo(address user) external view returns (uint256 totalShares, uint256 totalAssets, uint256 totalDeposits, uint256 totalWithdrawals, uint256 firstDepositTime) {
        totalShares = balanceOf(user);
        totalAssets = convertToAssets(totalShares);
        totalDeposits = userTotalDeposited[user];
        totalWithdrawals = userTotalWithdrawn[user];
        firstDepositTime = userFirstDepositTime[user];
    }

    function getVaultStats() external view returns (uint256 totalValueLocked, uint256 activeUsers, uint256 feesCollected, uint256 currentMaxDeposit, uint256 currentMaxWithdraw, uint256 currentManagementFee) {
        totalValueLocked = totalAssets();
        activeUsers = totalUsers;
        feesCollected = totalFeesCollected;
        currentMaxDeposit = maxDepositLimit;
        currentMaxWithdraw = maxWithdrawLimit;
        currentManagementFee = managementFee;
    }

    function canDeposit(address user, uint256 amount) external view {
        if (paused()) {
            revert VaultUSDC__VaultPaused();
        }
        if (amount == 0) {
            revert VaultUSDC__ZeroAmount();
        }
        if (amount > maxDepositLimit) {
            revert VaultUSDC__DepositExceedsLimit();
        }
        if (user == address(0)) {
            revert VaultUSDC__InvalidUserAddress();
        }
    }

    function canWithdraw(address user, uint256 amount) external view {
        if (paused()) {
            revert VaultUSDC__VaultPaused();
        }
        if (amount == 0) {
            revert VaultUSDC__ZeroAmount();
        }
        if (amount > maxWithdrawLimit) {
            revert VaultUSDC__WithdrawExceedsLimit();
        }
        uint256 userAssets = convertToAssets(balanceOf(user));
        if (amount > userAssets) {
            revert VaultUSDC__InsufficientBalance();
        }
    }

    function updateVaultParameters(uint256 _maxDeposit, uint256 _maxWithdraw, uint256 _managementFee) external onlyOwner {
        require(_managementFee <= 1000, "Fee cannot exceed 10%");
        
        emit VaultParametersUpdated(maxDepositLimit, _maxDeposit, maxWithdrawLimit, _maxWithdraw, managementFee, _managementFee);

        maxDepositLimit = _maxDeposit;
        maxWithdrawLimit = _maxWithdraw;
        managementFee = _managementFee;
    }

    function pause() external onlyOwner {
        _pause();
        emit EmergencyAction("PAUSED", msg.sender, block.timestamp);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit EmergencyAction("UNPAUSED", msg.sender, block.timestamp);
    }

    function emergencyWithdraw() external onlyOwner whenPaused {
        uint256 balance = IERC20(asset()).balanceOf(address(this));
        if (balance > 0) {
            IERC20(asset()).safeTransfer(owner(), balance);
            emit EmergencyAction("EMERGENCY_WITHDRAW", msg.sender, block.timestamp);
        }
    }

}