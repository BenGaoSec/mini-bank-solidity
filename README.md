# MiniBank — Minimal, Auditor-Style ETH Bank (Solidity)

A clean, security-focused implementation of a simple ETH bank.  
Designed to demonstrate **professional smart-contract structure**, including:

- Custom errors (gas-efficient & explicit)
- CEI (checks-effects-interactions) pattern
- ReentrancyGuard with uint256 status flag
- Minimalist ownership module (SimpleOwner)
- Explicit fallback/receive behavior
- Clear invariants documented in comments
- Small, predictable, “boring” architecture

This project is intentionally simple, but written with **auditor-grade discipline** to build correct habits from the beginning.

---

## ✨ Features

- Deposit ETH
- Withdraw ETH securely (nonReentrant)
- Owner can toggle deposit availability
- User balances tracked internally
- Receive() deposits automatically
- No interest, no ERC20, no external dependencies

---

## 🧱 Contract Architecture

contracts/
├── SimpleOwner.sol # Minimal admin module
├── ReentrancyGuard.sol # Standard uint256 reentrancy guard
└── MiniBank.sol # Core business logic

yaml
Copy code

This structure mirrors real protocol design:
- **ownership isolated**
- **reentrancy protection isolated**
- **business logic clean and focused**

---

## 🔐 Security Principles

This contract follows several important security patterns:

### ✔ Custom Errors  
Cheaper and clearer than require() strings.

### ✔ CEI Pattern  
State updated before sending ETH.

### ✔ Reentrancy Protection  
Function-level protection using `_status` flag.

### ✔ Minimal Attack Surface  
No complex inheritance, no proxies, no external token support.

### ✔ Explicit Receive Logic  
Avoid ambiguity around direct ETH sends.

---

## 🧪 Testing (Hardhat)

Tests written in TypeScript.

yarn install
npx hardhat test

yaml
Copy code

---

## 📦 Deployment

Example Hardhat script:

```ts
const MiniBank = await ethers.getContractFactory("MiniBank");
const bank = await MiniBank.deploy(deployer.address);
await bank.waitForDeployment();