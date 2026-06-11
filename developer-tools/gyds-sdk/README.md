# @gydschain/sdk — GYDS Chain JavaScript / TypeScript SDK

Zero-dependency TypeScript SDK for interacting with GYDS Chain (Chain ID 13370).

## Install

```bash
npm install @gydschain/sdk
# or copy src/index.ts into your project directly (no npm publish yet)
```

## Quick Start

```typescript
import { GYDSClient } from '@gydschain/sdk';

const gyds = new GYDSClient({ rpcUrl: 'http://YOUR_RPC_NODE_IP' });

// Block info
const height = await gyds.getBlockNumber();
const block  = await gyds.getLatestBlock(true); // true = include full txns
console.log(`Block #${height}:`, block);

// Balance
const wei    = await gyds.getBalance('0xYourAddress');
const pretty = await gyds.getBalanceInGyds('0xYourAddress');
console.log(`Balance: ${pretty} GYDS`);

// Send raw transaction
const txHash = await gyds.sendRawTransaction('0x...');
const receipt = await gyds.waitForTransaction(txHash);
console.log('Confirmed in block:', receipt.blockNumber);

// GYDS custom methods
const validators = await gyds.getValidatorSet();
console.log('Active validators:', validators.validators.map(v => v.address));
```

## Full API

### Chain Info
| Method                 | Returns      | Description                        |
|------------------------|--------------|------------------------------------|
| `getChainId()`         | `number`     | Chain ID (13370)                   |
| `getBlockNumber()`     | `number`     | Latest block height                |
| `getGasPrice()`        | `bigint`     | Current gas price in wei           |
| `getGasPriceInGwei()`  | `string`     | e.g. `"1.00 Gwei"`                 |
| `isConnected()`        | `boolean`    | Ping the RPC node                  |

### Blocks
| Method                              | Returns          | Description                |
|-------------------------------------|------------------|----------------------------|
| `getLatestBlock(full?)`             | `Block`          | Latest block               |
| `getBlockByNumber(n, full?)`        | `Block \| null`  | By block number            |
| `getBlockByHash(hash, full?)`       | `Block \| null`  | By block hash              |
| `getBlockRange(from, to)`           | `Block[]`        | Batch fetch multiple blocks |

### Accounts
| Method                          | Returns   | Description               |
|---------------------------------|-----------|---------------------------|
| `getBalance(addr)`              | `bigint`  | Balance in wei            |
| `getBalanceInGyds(addr)`        | `string`  | e.g. `"1.500000 GYDS"`   |
| `getNonce(addr)`                | `number`  | Transaction count / nonce |
| `getCode(addr)`                 | `string`  | Contract bytecode         |
| `isContract(addr)`              | `boolean` | True if contract          |

### Transactions
| Method                              | Returns                 | Description            |
|-------------------------------------|-------------------------|------------------------|
| `sendRawTransaction(hex)`           | `string`                | TX hash               |
| `getTransactionByHash(hash)`        | `Transaction \| null`   |                        |
| `getTransactionReceipt(hash)`       | `TransactionReceipt \| null` |                   |
| `estimateGas(tx)`                   | `number`                | Gas estimate           |
| `call_contract(tx, block?)`         | `string`                | eth_call               |
| `waitForTransaction(hash)`          | `TransactionReceipt`    | Polls until confirmed  |

### GYDS Custom
| Method              | Returns        | Description                    |
|---------------------|----------------|--------------------------------|
| `getValidatorSet()` | `ValidatorSet` | Active validators + epoch info |
| `getNodeInfo()`     | `NodeInfo`     | Node version, peers, etc.      |

### Utilities
```typescript
import { utils, GYDS_CHAIN_ID } from '@gydschain/sdk';

utils.weiToGyds(1_000_000_000_000_000_000n); // "1.000000"
utils.gydsToWei(1.5);                         // 1500000000000000000n
utils.shortAddress('0xAbcdef...');            // "0xAbcdef…1234"
```

## Batch Calls

```typescript
const results = await gyds.batch([
  { method: 'eth_blockNumber' },
  { method: 'eth_gasPrice' },
  { method: 'gyds_validatorSet' },
]);
```

## Chain Config

```typescript
import { GYDS_CHAIN_ID, GYDS_CHAIN_ID_HEX, GYDS_SYMBOL, GYDS_DECIMALS } from '@gydschain/sdk';

// Add to MetaMask programmatically:
await window.ethereum.request({
  method: 'wallet_addEthereumChain',
  params: [{
    chainId:          GYDS_CHAIN_ID_HEX,
    chainName:        'GYDS Chain',
    nativeCurrency:   { name: GYDS_SYMBOL, symbol: GYDS_SYMBOL, decimals: GYDS_DECIMALS },
    rpcUrls:          ['http://YOUR_RPC_NODE_IP'],
    blockExplorerUrls: null,
  }],
});
```
