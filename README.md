# ERC-4626 Yield Vault

A tokenized ERC-4626 yield vault with virtual share offset inflation attack protection, reentrancy guards, and performance fee accounting, written in **Solidity ^0.8.20** and tested with **Foundry**.

## Core Features & Architecture

- **Inflation / Donation Attack Protection:**
  - Implements `_decimalsOffset() = 3` (equivalent to 1,000 virtual shares) to mathematically neutralize first-depositor share inflation and donation exploits.
- **EIP-4626 Rounding Direction Compliance:**
  - Shares rounded down on deposit and mint in favor of the vault.
  - Assets rounded up on withdraw and redeem in favor of the vault.
  - Prevents arbitrage and free-share generation.
- **Safety Checks:**
  - Rejection of 0-share deposits and 0-asset withdrawals.
  - Strict over-withdrawal and over-redemption bounds checks.
  - Reentrancy protection on all entry points.
- **Performance Fee Accounting:**
  - Documented fee on recognized yield minted as shares to a designated fee recipient without diluting user principal.

## Project Structure

```
├── foundry.toml
├── src/
│   └── YieldVault.sol
├── script/
│   └── YieldVault.s.sol
└── test/
    ├── YieldVault.t.sol
    └── mocks/
        └── MockERC20.sol
```

## Getting Started

### Prerequisites
- [Foundry](https://getfoundry.sh/)

### Build
```bash
forge build
```

### Run Tests
```bash
forge test -vvv
```

All 9 test vectors pass, verifying first deposit offset, multi-depositor fairness, yield gains, donation attack resistance, rounding invariants, and fuzz testing.
