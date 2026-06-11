/**
 * @gydschain/sdk — JavaScript/TypeScript SDK for GYDS Chain (Chain ID 13370)
 *
 * Usage:
 *   import { GYDSClient } from '@gydschain/sdk';
 *   const gyds = new GYDSClient({ rpcUrl: 'http://your-rpcnode-ip' });
 *
 *   const height = await gyds.getBlockNumber();
 *   const block  = await gyds.getBlockByNumber(height);
 *   const bal    = await gyds.getBalance('0xYourAddress');
 */

import type {
  GYDSClientConfig,
  Block,
  Transaction,
  TransactionReceipt,
  ValidatorSet,
  NodeInfo,
  SyncStatus,
  Log,
  RPCResponse,
} from './types';

export * from './types';

// ── Constants ───────────────────────────────────────────────
export const GYDS_CHAIN_ID     = 13370;
export const GYDS_CHAIN_ID_HEX = '0x343A';
export const GYDS_SYMBOL       = 'GYDS';
export const GYDS_DECIMALS     = 18;

// ── Helpers ─────────────────────────────────────────────────
function hexToNum(hex: string): number {
  return parseInt(hex, 16);
}
function hexToBig(hex: string): bigint {
  return BigInt(hex);
}
function numToHex(n: number | bigint): string {
  return '0x' + n.toString(16);
}
function weiToGyds(wei: bigint, decimals = 6): string {
  const whole = wei / BigInt(1e18);
  const frac  = (wei % BigInt(1e18)) * BigInt(10 ** decimals) / BigInt(1e18);
  return `${whole}.${frac.toString().padStart(decimals, '0')}`;
}

// ── GYDSClient ──────────────────────────────────────────────
export class GYDSClient {
  private rpcUrl:    string;
  private timeoutMs: number;
  private idCounter = 0;

  constructor(config: GYDSClientConfig) {
    this.rpcUrl    = config.rpcUrl.replace(/\/$/, '');
    this.timeoutMs = config.timeoutMs ?? 10_000;
  }

  // ── Core RPC ─────────────────────────────────────────────
  async call<T = unknown>(method: string, params: unknown[] = []): Promise<T> {
    const id  = ++this.idCounter;
    const body = JSON.stringify({ jsonrpc: '2.0', method, params, id });

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    let res: Response;
    try {
      res = await fetch(this.rpcUrl, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body,
        signal:  controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }

    if (!res.ok) {
      throw new Error(`HTTP ${res.status}: ${res.statusText}`);
    }

    const json = (await res.json()) as RPCResponse<T>;
    if (json.error) {
      throw new Error(`RPC ${json.error.code}: ${json.error.message}`);
    }
    if (json.result === undefined) {
      throw new Error(`RPC returned no result for method: ${method}`);
    }
    return json.result;
  }

  /** Send a batch of RPC calls in one request */
  async batch(calls: { method: string; params?: unknown[] }[]): Promise<unknown[]> {
    const requests = calls.map((c, i) => ({
      jsonrpc: '2.0', method: c.method, params: c.params ?? [], id: ++this.idCounter,
    }));
    const res  = await fetch(this.rpcUrl, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(requests),
    });
    const json = (await res.json()) as RPCResponse[];
    return json.map(r => r.result);
  }

  // ── Chain Info ────────────────────────────────────────────
  async getChainId():       Promise<number>  { return hexToNum(await this.call<string>('eth_chainId')); }
  async getNetworkId():     Promise<string>  { return this.call<string>('net_version'); }
  async getClientVersion(): Promise<string>  { return this.call<string>('web3_clientVersion'); }
  async getPeerCount():     Promise<number>  { return hexToNum(await this.call<string>('net_peerCount')); }
  async isListening():      Promise<boolean> { return this.call<boolean>('net_listening'); }

  async getSyncStatus(): Promise<SyncStatus> {
    const result = await this.call<boolean | object>('eth_syncing');
    if (result === false) return { syncing: false };
    const s = result as { startingBlock: string; currentBlock: string; highestBlock: string };
    return {
      syncing:       true,
      startingBlock: hexToNum(s.startingBlock),
      currentBlock:  hexToNum(s.currentBlock),
      highestBlock:  hexToNum(s.highestBlock),
    };
  }

  // ── Block Methods ─────────────────────────────────────────
  async getBlockNumber(): Promise<number> {
    return hexToNum(await this.call<string>('eth_blockNumber'));
  }

  async getBlockByNumber(numberOrTag: number | 'latest' | 'earliest', full = false): Promise<Block | null> {
    const tag = typeof numberOrTag === 'number' ? numToHex(numberOrTag) : numberOrTag;
    const raw  = await this.call<Record<string, unknown> | null>('eth_getBlockByNumber', [tag, full]);
    return raw ? this.parseBlock(raw) : null;
  }

  async getBlockByHash(hash: string, full = false): Promise<Block | null> {
    const raw = await this.call<Record<string, unknown> | null>('eth_getBlockByHash', [hash, full]);
    return raw ? this.parseBlock(raw) : null;
  }

  async getLatestBlock(full = false): Promise<Block | null> {
    return this.getBlockByNumber('latest', full);
  }

  private parseBlock(raw: Record<string, unknown>): Block {
    return {
      number:          hexToNum(raw.number as string),
      hash:            raw.hash as string,
      parentHash:      raw.parentHash as string,
      validator:       raw.miner as string,
      timestamp:       hexToNum(raw.timestamp as string),
      gasLimit:        hexToNum(raw.gasLimit as string),
      gasUsed:         hexToNum(raw.gasUsed as string),
      transactions:    raw.transactions as string[],
      size:            hexToNum(raw.size as string),
      difficulty:      raw.difficulty as string,
      totalDifficulty: raw.totalDifficulty as string,
    };
  }

  // ── Transaction Methods ───────────────────────────────────
  async getTransactionByHash(hash: string): Promise<Transaction | null> {
    const raw = await this.call<Record<string, unknown> | null>('eth_getTransactionByHash', [hash]);
    return raw ? this.parseTx(raw) : null;
  }

  async getTransactionReceipt(hash: string): Promise<TransactionReceipt | null> {
    const raw = await this.call<Record<string, unknown> | null>('eth_getTransactionReceipt', [hash]);
    if (!raw) return null;
    return {
      transactionHash:   raw.transactionHash as string,
      transactionIndex:  hexToNum(raw.transactionIndex as string),
      blockHash:         raw.blockHash as string,
      blockNumber:       hexToNum(raw.blockNumber as string),
      from:              raw.from as string,
      to:                (raw.to as string) || null,
      gasUsed:           hexToNum(raw.gasUsed as string),
      cumulativeGasUsed: hexToNum(raw.cumulativeGasUsed as string),
      contractAddress:   (raw.contractAddress as string) || null,
      logs:              (raw.logs as unknown[]).map(l => l as Log),
      status:            raw.status as '0x0' | '0x1',
    };
  }

  async sendRawTransaction(signedTxHex: string): Promise<string> {
    return this.call<string>('eth_sendRawTransaction', [signedTxHex]);
  }

  async estimateGas(tx: { from?: string; to?: string; value?: bigint; data?: string }): Promise<number> {
    const rpcTx: Record<string, string> = {};
    if (tx.from)  rpcTx.from  = tx.from;
    if (tx.to)    rpcTx.to    = tx.to;
    if (tx.value) rpcTx.value = numToHex(tx.value);
    if (tx.data)  rpcTx.data  = tx.data;
    return hexToNum(await this.call<string>('eth_estimateGas', [rpcTx]));
  }

  async call_contract(tx: { from?: string; to: string; data: string }, block = 'latest'): Promise<string> {
    return this.call<string>('eth_call', [tx, block]);
  }

  private parseTx(raw: Record<string, unknown>): Transaction {
    return {
      hash:             raw.hash as string,
      from:             raw.from as string,
      to:               (raw.to as string) || null,
      value:            hexToBig(raw.value as string),
      gas:              hexToNum(raw.gas as string),
      gasPrice:         hexToBig(raw.gasPrice as string),
      nonce:            hexToNum(raw.nonce as string),
      input:            raw.input as string,
      blockHash:        (raw.blockHash as string) || null,
      blockNumber:      raw.blockNumber ? hexToNum(raw.blockNumber as string) : null,
      transactionIndex: raw.transactionIndex ? hexToNum(raw.transactionIndex as string) : null,
      type:             raw.type as string,
    };
  }

  // ── Account Methods ───────────────────────────────────────
  async getBalance(address: string, block = 'latest'): Promise<bigint> {
    return hexToBig(await this.call<string>('eth_getBalance', [address, block]));
  }

  async getBalanceInGyds(address: string, block = 'latest'): Promise<string> {
    const wei = await this.getBalance(address, block);
    return weiToGyds(wei);
  }

  async getNonce(address: string, block = 'latest'): Promise<number> {
    return hexToNum(await this.call<string>('eth_getTransactionCount', [address, block]));
  }

  async getCode(address: string, block = 'latest'): Promise<string> {
    return this.call<string>('eth_getCode', [address, block]);
  }

  async getStorageAt(address: string, slot: string, block = 'latest'): Promise<string> {
    return this.call<string>('eth_getStorageAt', [address, slot, block]);
  }

  async isContract(address: string): Promise<boolean> {
    const code = await this.getCode(address);
    return code !== '0x' && code !== '0x0' && code.length > 2;
  }

  // ── Gas ───────────────────────────────────────────────────
  async getGasPrice(): Promise<bigint> {
    return hexToBig(await this.call<string>('eth_gasPrice'));
  }

  async getGasPriceInGwei(): Promise<string> {
    const wei = await this.getGasPrice();
    return (Number(wei) / 1e9).toFixed(2) + ' Gwei';
  }

  // ── GYDS Custom Methods ───────────────────────────────────
  async getValidatorSet(): Promise<ValidatorSet> {
    return this.call<ValidatorSet>('gyds_validatorSet', []);
  }

  async getNodeInfo(): Promise<NodeInfo> {
    return this.call<NodeInfo>('gyds_nodeInfo', []);
  }

  // ── Health / Utility ──────────────────────────────────────
  async isConnected(): Promise<boolean> {
    try {
      await this.getBlockNumber();
      return true;
    } catch {
      return false;
    }
  }

  async waitForTransaction(hash: string, pollMs = 2000, timeoutMs = 60_000): Promise<TransactionReceipt> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const receipt = await this.getTransactionReceipt(hash);
      if (receipt) return receipt;
      await new Promise(r => setTimeout(r, pollMs));
    }
    throw new Error(`Transaction ${hash} not confirmed within ${timeoutMs}ms`);
  }

  /** Fetch multiple blocks at once using batch RPC */
  async getBlockRange(from: number, to: number): Promise<(Block | null)[]> {
    const calls = [];
    for (let i = from; i <= to; i++) {
      calls.push({ method: 'eth_getBlockByNumber', params: [numToHex(i), false] });
    }
    const results = await this.batch(calls);
    return results.map(r => r ? this.parseBlock(r as Record<string, unknown>) : null);
  }
}

// ── Utility exports ──────────────────────────────────────────
export const utils = {
  weiToGyds,
  hexToNum,
  hexToBig,
  numToHex,
  /** Convert GYDS to wei bigint */
  gydsToWei(gyds: number | string): bigint {
    const n = typeof gyds === 'string' ? parseFloat(gyds) : gyds;
    return BigInt(Math.round(n * 1e18));
  },
  /** Shorten an address: 0xAbCd…EfGh */
  shortAddress(addr: string, chars = 6): string {
    if (!addr || addr.length < 10) return addr;
    return addr.slice(0, chars + 2) + '…' + addr.slice(-4);
  },
  /** Zero-pad hex to 32 bytes */
  padHex32(hex: string): string {
    return '0x' + hex.replace(/^0x/, '').padStart(64, '0');
  },
};

// ── Default export ────────────────────────────────────────────
export default GYDSClient;

// ── Quick connect helper ──────────────────────────────────────
export function createClient(rpcUrl: string): GYDSClient {
  return new GYDSClient({ rpcUrl });
}
