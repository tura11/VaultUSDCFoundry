// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";



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
    error VaultUSDC__NoStrategySet();
    error VaultUSDC__InsufficientStrategyLiquidity(); 
    error VaultUSDC__NoShares();


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
    
    uint256 public constant TARGET_LIQUIDITY_BPS = 1500; // 15%
    uint256 public constant REBALANCE_THRESHOLD_BPS = 500; // 5%

   
    address public strategy;

    mapping(address => uint256) public userFirstDepositTime;
    mapping(address => uint256) public userTotalDeposited;
    mapping(address => uint256) public userTotalWithdrawn;
    mapping(address => uint256) public userCostBasis; 

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

        
        if (userCostBasis[receiver] == 0) {
            totalUsers++;
            userFirstDepositTime[receiver] = block.timestamp;
        }
        
        userCostBasis[receiver] += assetsAfterFee;
        userTotalDeposited[receiver] += assetsAfterFee;
        totalDeposited += assetsAfterFee;

      
        _rebalanceToStrategy();

        emit DepositExecuted(msg.sender, receiver, assets, shares, assetsFee, block.timestamp);

        return shares;
    }


    function _rebalanceToStrategy() public {
       
        if (strategy == address(0)) {
            revert VaultUSDC__NoStrategySet();
        }

        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        uint256 total = totalAssets();

        if (total == 0) {
            revert VaultUSDC__NoShares();
        }

        uint256 targetLiquidity = (total * TARGET_LIQUIDITY_BPS) / 10000;

        if(vaultBalance > targetLiquidity) {
            uint256 toSend = vaultBalance - targetLiquidity;
           
            IERC20(asset()).approve(strategy, toSend);
            IStrategy(strategy).deposit(toSend);
        }
    }

    function withdraw(uint256 assets, address receiver, address shareOwner) public override nonReentrant whenNotPaused validAmount(assets) validAddress(receiver) returns (uint256) {
        if (assets > maxWithdrawLimit) {
            revert VaultUSDC__WithdrawExceedsLimit();
        }

     
        uint256 shares = previewWithdraw(assets);

    
        if(msg.sender != shareOwner) {
            _spendAllowance(shareOwner, msg.sender, shares);
        }

       
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));

        if (assets > vaultBalance) { 
            uint256 needed = assets - vaultBalance;
            _withdrawFromStrategy(needed);
        }

        
        _burn(shareOwner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        if (totalDeposited >= assets) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }
        
        _updateCostBasisOnWithdraw(shareOwner, shares);
        userTotalWithdrawn[shareOwner] += assets;

        
        _checkAndRebalanceFromStrategy();

        emit WithdrawalExecuted(msg.sender, receiver, shareOwner, assets, shares, block.timestamp);

        return shares;
    }

    function _withdrawFromStrategy(uint256 amount) public {
        if(strategy == address(0)) {
            revert VaultUSDC__NoStrategySet();
        }

        uint256 withdrawn = IStrategy(strategy).withdraw(amount);
        
        if (withdrawn < amount) {
            revert VaultUSDC__InsufficientStrategyLiquidity(); 
        }
    } 

    function _checkAndRebalanceFromStrategy() internal {
        if (strategy == address(0)) {
            revert VaultUSDC__NoStrategySet();
        }

        
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        uint256 total = totalAssets();
        
        if (total == 0) return;
        
        uint256 currentRatio = (vaultBalance * 10000) / total;
        uint256 minRatio = TARGET_LIQUIDITY_BPS - REBALANCE_THRESHOLD_BPS; // 10%
        
        if (currentRatio < minRatio) {
            uint256 targetAmount = (total * TARGET_LIQUIDITY_BPS) / 10000;
            uint256 toWithdraw = targetAmount - vaultBalance;
            
            if (toWithdraw > 0) {
                try IStrategy(strategy).withdraw(toWithdraw) {
                    // Successfully withdrew from strategy
                } catch {
                    // Strategy doesn't have liquidity
                }
            }
        }
    }

    function _updateCostBasisOnWithdraw(address user, uint256 sharesBurned) internal {
        uint256 remainingShares = balanceOf(user);
        
        if (remainingShares == 0) {
            userCostBasis[user] = 0;
        } else {
            uint256 totalSharesBefore = remainingShares + sharesBurned;
            uint256 costReduction = (userCostBasis[user] * sharesBurned) / totalSharesBefore;
            userCostBasis[user] -= costReduction;
        }
    }

    function withdrawProfit(address receiver) external  whenNotPaused returns(uint256) { 
        uint256 userShares = balanceOf(msg.sender);
        if(userShares == 0) {
            revert VaultUSDC__NoShares();
        }

        uint256 currentValue = convertToAssets(userShares); 
        uint256 costBasis = userCostBasis[msg.sender];

        if(currentValue <= costBasis) {
            return 0;
        }

        uint256 profit = currentValue - costBasis;

        return withdraw(profit, receiver, msg.sender);
    }

    function totalAssets() public view override returns (uint256) {
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        uint256 strategyBalance = 0;
        
        if (strategy != address(0)) {
            strategyBalance = IStrategy(strategy).balanceOf();
        }
        
        return vaultBalance + strategyBalance;
    }

    function rebalance() external onlyOwner {
        _rebalanceToStrategy();
    }

    function updateTargetLiquidity(uint256 newTargetBPS) external onlyOwner {
        require(newTargetBPS <= 5000, "Max 50%");
        require(newTargetBPS >= 500, "Min 5%");
        

    }

    function emergencyWithdrawFromStrategy() external onlyOwner whenPaused {
        if (strategy != address(0)) {
            IStrategy(strategy).emergencyWithdraw();
        }
    }

    
    function setStrategy(address _strategy) external onlyOwner {
    if (_strategy == address(0)) revert VaultUSDC__NoStrategySet();
    strategy = _strategy;
    }

    function clearStrategy() external onlyOwner {
        address oldStrategy = strategy;
        strategy = address(0);
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