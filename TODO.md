# GYDS Chain — Project TODO

Tracked items for the GYDS Chain ecosystem. Check off items as they are completed.
Anyone picking up this project can use this file to understand what still needs to be built, fixed, or improved.

---

## Legend

- `[ ]` Not started
- `[~]` In progress
- `[x]` Done

---

## Public Node (rpcnode) — MUST stay public

The **rpcnode** is the only repo that should be public on GitHub.
Wallets, websites, dApps, and block explorers all connect through it.

### Web Dashboard
- [x] Dark-theme dashboard served at `GET /`
- [x] Real-time block height counter (auto-refresh every 5s)
- [x] Chain stats cards (block height, chain ID, gas price, block time)
- [x] "Add GYDS Chain to MetaMask" one-click button (`wallet_addEthereumChain`)
- [x] "Switch to GYDS Chain" button (when already added)
- [x] Trust Wallet manual setup fields with copy buttons
- [x] TLS warning banner (shows when running over HTTP)
- [x] Recent blocks table (last 20 blocks, auto-refresh)
- [x] Live RPC tester (click-to-run common methods)
- [x] Transaction search — type a tx hash and see full details
- [x] Address/wallet lookup — show balance, tx history, nonce
- [x] Block detail page — click a block row to see all transactions (modal)
- [x] Light mode / dark mode toggle (persists in localStorage)
- [x] Block chart — graph of tx count per block over time (inline SVG bars)
- [x] Validator stats panel — show current validator set and last proposed block
- [x] Mobile-responsive polish pass (tables, copy buttons, responsive columns)

### RPC / API
- [x] Full ETH JSON-RPC HTTP (`POST /`)
- [x] WebSocket subscriptions (`ws://:8546/api/ws`)
- [x] REST endpoints (`/api/blocks`, `/api/transactions`, `/api/accounts`)
- [x] Health check (`GET /health`)
- [x] CORS middleware
- [ ] `eth_getLogs` — implement log filtering against stored receipts
- [ ] `eth_getFilterChanges` — implement polling filters
- [ ] `debug_traceTransaction` — transaction trace for debugging
- [x] `gyds_validatorSet` — custom method returning current validator addresses
- [x] `gyds_nodeInfo` — custom method returning node version/peers/height
- [x] Batch JSON-RPC request support (existing — `[]` body dispatch)
- [ ] Request rate limiting per API key (for premium access tiers)

### Infrastructure
- [x] Nginx reverse proxy with rate limiting
- [x] Optional Certbot TLS (`--domain`)
- [x] Docker + Docker Compose
- [x] UFW firewall rules in setup script
- [x] fail2ban — custom jails + filters for all 4 nodes
- [x] Firewall hardening script (`setup-firewall.sh`) for all 4 nodes
- [x] Sysctl network hardening (SYN flood, IP spoofing, ICMP redirect)
- [x] SSH hardening (key-only, MaxAuthTries 3) on validator node
- [x] WireGuard VPN client on all 4 nodes (`setup-wireguard.sh`)
- [x] Validator RPC locked to VPN-only access (blocked from internet)
- [x] Health-check cron (auto-restart on failure)
- [ ] Load balancer config (HAProxy / Cloudflare) for high-availability
- [ ] Multiple RPC node instances behind a single domain
- [x] Prometheus metrics endpoint (`/metrics`) for Grafana monitoring
- [x] Pre-built Grafana dashboard JSON (import-ready, auto-provisioned)
- [x] Docker Compose monitoring stack (Prometheus + Grafana, one command)
- [x] Uptime status page (Uptime Kuma — Docker Compose + auto-monitor setup script)
- [ ] DDoS protection (Cloudflare proxy)
- [ ] Backup node with automatic failover

---

## Private Nodes — keep repos private

### All Private Nodes (shared)
- [x] P2P networking (port 30303)
- [x] LevelDB storage
- [x] Genesis block configuration (Chain ID 13370, GYDS)
- [x] Docker + Docker Compose
- [x] Automated server setup scripts
- [x] Gossip protocol — broadcast new transactions to all peers (`p2p/gossip.go`)
- [x] Block propagation — push new blocks to all connected peers in real time
- [x] Node discovery — automatic peer discovery via bootstrap nodes (discovery loop)
- [x] Checkpoint sync — fast-sync request via `RequestCheckpointSync()`
- [ ] Metrics / telemetry — internal Prometheus + Grafana dashboard

### Validator Node (validatornode) — private
- [x] ECDSA key pair generation (`keygen` subcommand)
- [x] Keystore file support (JSON encrypted key)
- [x] Localhost-only RPC (127.0.0.1)
- [x] PoS block proposal when selected as epoch leader
- [x] Block reward mechanism — mint GYDS to validator address on commit (`consensus/rewards.go`)
- [x] Slashing conditions — slash logic in `GYDSStaking.sol` smart contract
- [x] Validator on-chain registration — `GYDSStaking.sol` staking contract (32k GYDS min)
- [ ] Hardware wallet / HSM support for validator key (Ledger, YubiHSM)
- [ ] Multi-validator support — run multiple keys from one node
- [x] Uptime monitoring — `UptimeTracker` in `consensus/rewards.go`
- [ ] Graceful key rotation — replace validator key without downtime

### Full Node (fullnode) — private
- [ ] Full transaction mempool (accept, validate, propagate txs)
- [ ] Transaction receipt storage
- [ ] Event log indexing (for `eth_getLogs`)
- [ ] State pruning — remove old state to reclaim disk space
- [ ] Archive mode — keep full historical state for explorers

### Lite Node (litenode) — private
- [ ] Header-only sync (already basic — needs P2P gossip)
- [ ] Verify block headers via validator signatures
- [ ] Serve SPV proofs to wallets

### Boost Node (boostnode) — private
- [ ] High-speed block relay — rebroadcast blocks to all connected nodes
- [ ] Bootstrap peer list — serve peer addresses to new nodes joining the network
- [ ] Bandwidth throttling per peer

---

## Ecosystem — future repos / projects

### Block Explorer
- [ ] Create new repo: `explorer` (or deploy open-source explorer like Blockscout)
- [ ] Index all blocks, transactions, and addresses
- [ ] Address pages — balance, tx history
- [ ] Token transfer tracking
- [ ] Validator activity view
- [ ] API for the web dashboard block detail links

### Token / Smart Contracts
- [ ] ERC-20 GYDS token contract (if bridging to EVM chains)
- [ ] Staking contract — lock GYDS to earn validator rights
- [ ] Governance contract — on-chain voting for protocol upgrades
- [ ] Token vesting contract (for team / investor allocations)
- [ ] Faucet contract (testnet GYDS drip)

### Wallet / User Tools
- [ ] Web wallet — send/receive GYDS from the browser (no MetaMask required)
- [ ] Faucet website — testnet GYDS for developers
- [ ] Chain-aware QR code generator for receiving GYDS
- [ ] CSV export of transaction history for tax purposes

### Developer Tools
- [x] Hardhat config for deploying contracts to GYDS Chain (`developer-tools/hardhat/`)
- [x] SDK (JS/TS) — typed wrapper around the RPC and REST APIs (`developer-tools/gyds-sdk/`)
- [x] Sample contracts — `GYDSFaucet.sol` + `GYDSStaking.sol`
- [ ] Chain documentation website
- [ ] Testnet deployment (separate Chain ID)

### Security
- [ ] Smart contract audit (when staking / governance contracts are ready)
- [ ] Penetration test on public rpcnode (Nginx, RPC surface)
- [x] fail2ban + firewall hardening on all 4 nodes
- [ ] Bug bounty program
- [ ] Incident response playbook

---

## Done ✅

- [x] `fullnode` — complete full node codebase with RPC
- [x] `litenode` — lightweight sync node
- [x] `boostnode` — high-throughput relay node
- [x] `validatornode` — PoS block producer with key management
- [x] `rpcnode` — dedicated public RPC/WebSocket endpoint
- [x] Chain ID 13370, Symbol GYDS, Decimals 18
- [x] Docker support for all nodes
- [x] Automated server setup scripts for all nodes
- [x] README with MetaMask/Trust Wallet config in rpcnode
- [x] README with validator registration steps in validatornode
- [x] Web dashboard with MetaMask one-click connect
- [x] GYDS network info in dashboard (auto-detects server URL)

---

*Last updated: 2026-06-11*
