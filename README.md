# 🏦 VaultUSDC - ERC4626 Yield Vault

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-e6e6e6?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> A sophisticated ERC4626-compliant USDC vault with automated Aave strategy integration, management fees, and intelligent liquidity rebalancing.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Smart Contracts](#smart-contracts)
- [Installation](#installation)
- [Testing](#testing)
- [Deployment](#deployment)
- [Usage](#usage)
- [Security](#security)
- [Gas Optimization](#gas-optimization)
- [License](#license)

## 🎯 Overview

VaultUSDC is a production-ready DeFi vault that allows users to deposit USDC and earn yield through automated Aave lending strategies. The vault implements the ERC4626 tokenized vault standard, providing a secure and standardized interface for yield-bearing deposits.

### Key Metrics

- **Standard**: ERC4626 Compliant
- **Underlying Asset**: USDC
- **Management Fee**: 2% (configurable, max 10%)
- **Target Liquidity**: 15% (configurable 5-50%)
- **Max Single Deposit**: 1M USDC (configurable)
- **Max Single Withdrawal**: 100K USDC (configurable)

## ✨ Features

### Core Functionality

- ✅ **ERC4626 Standard**: Full compliance with tokenized vault standard
- ✅ **Automated Strategy**: Seamless integration with Aave lending protocol
- ✅ **Intelligent Rebalancing**: Automatic liquidity management between vault and strategy
- ✅ **Management Fees**: Configurable fees on deposits (default 2%)
- ✅ **Profit Tracking**: Individual user cost basis and profit calculation
- ✅ **Emergency Controls**: Pausable with emergency withdrawal mechanisms

### Advanced Features

- 📊 **Multi-User Support**: Track deposits, withdrawals, and profits per user
- 🔄 **Dynamic Rebalancing**: Maintains optimal liquidity ratio (15% default)
- 💰 **Profit Withdrawal**: Withdraw only gains above cost basis
- 🛡️ **Security**: ReentrancyGuard, Pausable, and Ownable patterns
- 📈 **Analytics**: Comprehensive vault and user statistics

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      VaultUSDC                          │
│  (ERC4626 + Management Fees + User Tracking)            │
│                                                         │
│  • Receives USDC deposits                               │
│  • Mints vault shares (vUSDC)                           │
│  • Automatically rebalances to strategy                 │
│  • Tracks user cost basis for profit calculation        │
└────────────────┬────────────────────────────────────────┘
                 │
                 │ Rebalancing (85% of funds)
                 ▼
┌─────────────────────────────────────────────────────────┐
│                   AaveYieldFarm                         │
│         (Strategy - Aave Integration)                   │
│                                                         │
│  • Deposits USDC to Aave                                │
│  • Receives aUSDC (yield-bearing tokens)                │
│  • Harvests yield automatically                         │
│  • Provides liquidity when vault needs funds            │
└────────────────┬────────────────────────────────────────┘
                 │
                 │ Lending
                 ▼
┌─────────────────────────────────────────────────────────┐
│                  Aave Lending Pool                      │
│            (External Protocol)                          │
│                                                         │
│  • Generates yield on deposits                          │
│  • Returns aUSDC tokens                                 │
└─────────────────────────────────────────────────────────┘
```

## 📦 Smart Contracts

### Core Contracts

#### `VaultUSDC.sol`
Main vault contract implementing ERC4626 standard with additional features:
- Deposit/withdrawal with management fees
- Automated rebalancing to strategy
- User tracking and profit calculation
- Emergency controls

#### `AaveYieldFarm.sol`
Strategy contract for Aave integration:
- Deposits USDC to Aave lending pool
- Receives aUSDC (interest-bearing tokens)
- Harvest yield functionality
- Emergency withdrawal support

### Interfaces

- `IStrategy.sol` - Strategy interface for vault integration
- `IAaveLendingPool.sol` - Aave lending pool interface

## 🚀 Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/downloads)
- Node.js (optional, for additional tooling)

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/vault-usdc.git
cd vault-usdc

# Install dependencies
forge install

# Build the project
forge build

# Run tests
forge test
```

### Dependencies

```bash
forge install OpenZeppelin/openzeppelin-contracts
```

## 🧪 Testing

The project includes comprehensive test coverage:

### Test Structure

```
test/
├── unit/
│   ├── VaultUSDC.t.sol          # Unit tests for vault
│   └── AaveYieldFarm.t.sol      # Unit tests for strategy
├── fuzz/
│   └── VaultUSDCFuzz.t.sol      # Fuzz tests
└── invariant/
    └── VaultInvariant.t.sol     # Invariant tests
```

### Running Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/unit/VaultUSDC.t.sol

# Run with gas report
forge test --gas-report

# Run fuzz tests with custom runs
forge test --match-contract VaultUSDCFuzzTest --fuzz-runs 10000

# Run invariant tests
forge test --match-contract VaultUSDCInvariantTest

# Check coverage
forge coverage
```

### Test Coverage

```bash
# Generate coverage report
forge coverage

# Generate detailed HTML report
forge coverage --report lcov
genhtml lcov.info -o coverage
open coverage/index.html
```

Current coverage: **>95%** on all contracts

## 📤 Deployment

### Local Deployment

```bash
# Start local anvil node
anvil

# Deploy contracts
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Testnet Deployment

```bash
# Deploy to Sepolia
forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Mainnet Deployment

```bash
# Deploy to mainnet (USE WITH CAUTION)
forge script script/Deploy.s.sol \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## 💡 Usage

### For Users

#### Depositing USDC

```solidity
// Approve USDC
IERC20(usdc).approve(address(vault), amount);

// Deposit and receive shares
uint256 shares = vault.deposit(amount, msg.sender);
```

#### Withdrawing USDC

```solidity
// Withdraw specific amount
uint256 sharesBurned = vault.withdraw(amount, msg.sender, msg.sender);

// Or redeem all shares
uint256 assetsReceived = vault.redeem(shares, msg.sender, msg.sender);
```

#### Withdrawing Only Profit

```solidity
// Withdraw only gains above cost basis
uint256 sharesBurned = vault.withdrawProfit(msg.sender);
```

#### Checking Balance

```solidity
// Get share balance
uint256 shares = vault.balanceOf(user);

// Convert to assets
uint256 assets = vault.convertToAssets(shares);

// Get detailed user info
(
    uint256 totalShares,
    uint256 totalAssets,
    uint256 totalDeposits,
    uint256 totalWithdrawals,
    uint256 firstDepositTime
) = vault.getUserInfo(user);
```

### For Administrators

#### Managing Strategy

```solidity
// Set strategy
vault.setStrategy(strategyAddress);

// Manually trigger rebalance
vault.rebalance();

// Update target liquidity (15% default)
vault.updateTargetLiquidity(2000); // 20%
```

#### Managing Parameters

```solidity
// Update vault parameters
vault.updateVaultParameters(
    2000000e6,  // maxDeposit: 2M USDC
    200000e6,   // maxWithdraw: 200K USDC
    300         // managementFee: 3%
);
```

#### Emergency Controls

```solidity
// Pause vault
vault.pause();

// Unpause vault
vault.unpause();

// Emergency withdraw from strategy
vault.emergencyWithdrawFromStrategy();

// Emergency withdraw from vault
vault.emergencyWithdraw();
```

## 🔒 Security

### Security Measures

- ✅ **ReentrancyGuard**: Protection against reentrancy attacks
- ✅ **Pausable**: Emergency pause functionality
- ✅ **Access Control**: Owner-only administrative functions
- ✅ **SafeERC20**: Safe token transfers
- ✅ **Custom Errors**: Gas-efficient error handling
- ✅ **Input Validation**: Comprehensive parameter checks

### Audits

⚠️ **This project has NOT been audited.** Use at your own risk.

### Known Issues

- Functions `_rebalanceToStrategy()`, `_withdrawFromStrategy()`, and `_checkAndRebalanceFromStrategy()` are marked as `public` but should be `internal` (for testing purposes)

### Bug Bounty

Currently no bug bounty program. Please report security issues to: [your-email@example.com]

## ⚡ Gas Optimization

### Optimizations Implemented

- Custom errors instead of require strings
- Immutable variables where applicable
- Efficient storage packing
- Minimal external calls
- Batch operations support

### Gas Benchmarks

| Operation | Gas Cost |
|-----------|----------|
| Deposit (first time) | ~180,000 |
| Deposit (subsequent) | ~120,000 |
| Withdraw | ~150,000 |
| Harvest | ~100,000 |

## 📊 Statistics

### Vault Statistics

```solidity
(
    uint256 totalValueLocked,
    uint256 activeUsers,
    uint256 feesCollected,
    uint256 currentMaxDeposit,
    uint256 currentMaxWithdraw,
    uint256 currentManagementFee
) = vault.getVaultStats();
```

### User Statistics

```solidity
// Check user's total deposited
uint256 deposited = vault.userTotalDeposited(user);

// Check user's total withdrawn
uint256 withdrawn = vault.userTotalWithdrawn(user);

// Check user's cost basis
uint256 costBasis = vault.userCostBasis(user);

// Check user's first deposit time
uint256 firstDeposit = vault.userFirstDepositTime(user);
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file:

```bash
# RPC URLs
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY

# Private Keys (NEVER COMMIT THESE)
PRIVATE_KEY=0x...

# Etherscan
ETHERSCAN_API_KEY=YOUR_KEY

# Contract Addresses
USDC_ADDRESS=0x...
AAVE_POOL_ADDRESS=0x...
AUSDC_ADDRESS=0x...
```

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Write comprehensive tests for new features
- Maintain test coverage above 90%
- Follow Solidity style guide
- Add NatSpec comments to all public functions
- Update documentation for new features

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- OpenZeppelin for secure contract libraries
- Foundry for excellent development framework
- Aave for lending protocol integration
- ERC4626 standard authors

## 📞 Contact

- **Author**: Tura11
- **Twitter**: [@yourtwitter](https://twitter.com/yourtwitter)
- **Discord**: your-discord
- **Email**: your-email@example.com

## 🗺️ Roadmap

### Version 1.0 (Current)
- ✅ ERC4626 vault implementation
- ✅ Aave strategy integration
- ✅ Management fees
- ✅ User tracking
- ✅ Emergency controls

### Version 1.1 (Planned)
- ⏳ Multiple strategy support
- ⏳ Strategy allocation weights
- ⏳ Performance fees
- ⏳ Governance token

### Version 2.0 (Future)
- 🔮 Cross-chain deployment
- 🔮 Additional DeFi protocols
- 🔮 Auto-compounding strategies
- 🔮 DAO governance

---

<div align="center">

**⭐ Star us on GitHub — it helps!**

[Report Bug](https://github.com/yourusername/vault-usdc/issues) · [Request Feature](https://github.com/yourusername/vault-usdc/issues)

Made with ❤️ by Tura11

</div>
