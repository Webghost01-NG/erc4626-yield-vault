# ERC-4626 Yield Vault

> **What it is about:** A standardized, tokenized DeFi yield vault adhering strictly to the ERC-4626 tokenized vault specification.
>
> **What it does:** Accepts deposits of an underlying ERC-20 token and issues yield-bearing shares whose exchange rate increases as profits accumulate, protects depositors against share inflation and donation exploits via a virtual share offset, enforces directional rounding in favor of the vault, and mints a documented performance fee on recognized yield.

---

## Key Features & Architecture

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
