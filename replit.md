# GYDS Chain Litenode

A lightweight blockchain node for the GYDS Chain (Chain ID 13370). Written in Go, it provides an ETH-compatible JSON-RPC API, WebSocket subscriptions, P2P networking, and a built-in web dashboard.

## How to run

The workflow **Start application** builds and starts the node automatically:

```
GOTOOLCHAIN=local go run . start
```

The web dashboard is served at port **5000** (RPC HTTP). WebSocket subscriptions run on port **8546**.

## Environment variables

Set in Replit's environment (Secrets / Env Vars panel):

| Variable | Default | Description |
|---|---|---|
| `GYDS_CHAIN_ID` | `13370` | Chain ID |
| `GYDS_NODE_MODE` | `lite` | Node mode (`lite` or `full`) |
| `GYDS_RPC_PORT` | `5000` | HTTP RPC port |
| `GYDS_RPC_HOST` | `0.0.0.0` | RPC bind host |
| `GYDS_WS_PORT` | `8546` | WebSocket port |
| `GYDS_P2P_PORT` | `30305` | P2P networking port |
| `GYDS_DATA_DIR` | `./data` | Storage directory |
| `GYDS_LOG_LEVEL` | `info` | Log level (`trace`/`debug`/`info`/`warn`/`error`) |
| `GYDS_BOOTSTRAP_NODES` | _(empty)_ | Bootstrap peer address e.g. `tcp://node.gydschain.io:30303` |

## Key endpoints

- `GET /` — Web dashboard
- `POST /` — ETH JSON-RPC (e.g. `eth_blockNumber`, `eth_getBalance`, `eth_sendRawTransaction`)
- `GET /health` — Health check
- `GET /api/blocks` — Recent blocks (REST)
- `GET /api/transactions` — Recent transactions (REST)
- `GET /api/accounts` — Account list (REST)
- `ws://<host>:8546/api/ws` — WebSocket subscriptions
- `GET /metrics` — Prometheus metrics

## What was changed from the import

1. `go.mod` — downgraded `go 1.22` → `go 1.21` to match the Go version available on Replit
2. `core/chain.go` — fixed import path from `gydschain/rpcnode/storage` → `gydschain/litenode/storage`
3. `rpc/server.go` — fixed import path from `gydschain/rpcnode/core` → `gydschain/litenode/core`
4. `core/db.go` — added missing `openDB`, `loadFromDB`, `Close`, and `persistBlock` methods (in-memory storage backend)
5. `main.go` — updated calls to match actual function signatures (`NewChain`, `NewServer`, `BroadcastWS`)

## Stack

- **Language:** Go 1.21
- **Consensus:** Proof-of-Stake (5-second block time)
- **Storage:** In-memory (with interface for disk backends)
- **P2P:** Custom gossip protocol on port 30305
- **RPC:** ETH-compatible JSON-RPC + WebSocket
