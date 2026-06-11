# GYDS Chain — Hardhat Development Environment

Deploy smart contracts to **GYDS Chain (Chain ID 13370)** using Hardhat.

## Quick Start

```bash
cd developer-tools/hardhat
npm install
cp .env.example .env
# Edit .env — set your PRIVATE_KEY and GYDS_RPC
npm run compile
npm run deploy
```

## Network Config

| Field      | Value                        |
|------------|------------------------------|
| Chain ID   | `13370`                      |
| Symbol     | `GYDS`                       |
| Decimals   | `18`                         |
| RPC URL    | Your rpcnode IP/domain       |
| Gas Price  | `1 Gwei` (`1_000_000_000`)   |

## Included Contracts

### GYDSFaucet.sol
A testnet faucet that drips GYDS to wallets. Features:
- `request()` — claim 1 GYDS (24h cooldown per address)
- `drip(address)` — drip to any address
- Owner can change drip amount and cooldown
- Owner can withdraw and top-up

### GYDSStaking.sol
Validator staking contract. Features:
- Minimum stake: 32,000 GYDS
- `register()` — stake GYDS and become a validator
- `unstake()` — exit and recover stake
- `claimReward()` — claim earned block rewards
- Owner can slash double-signers

## Common Commands

```bash
# Compile all contracts
npm run compile

# Deploy to GYDS Chain
npm run deploy

# Deploy to local hardhat node
npm run deploy:local

# Open interactive console on GYDS Chain
npm run console

# Run tests
npm test
```

## Writing Your Own Contracts

1. Add `.sol` file to `contracts/`
2. Add deploy logic to `scripts/deploy.js`
3. `npm run compile && npm run deploy`

## MetaMask / Wallet Config

To interact with deployed contracts via MetaMask:
- Network: GYDS Chain
- Chain ID: 13370
- RPC: `http://YOUR_RPC_NODE_IP`
- Symbol: GYDS, Decimals: 18
