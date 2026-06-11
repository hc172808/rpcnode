// ── GYDS Chain SDK — Type Definitions ─────────────────────────

export interface GYDSClientConfig {
  /** RPC endpoint URL, e.g. "http://your-rpcnode-ip" */
  rpcUrl: string;
  /** Request timeout in milliseconds (default: 10000) */
  timeoutMs?: number;
}

export interface Block {
  number:           number;
  hash:             string;
  parentHash:       string;
  validator:        string;   // miner field = proposer in PoS
  timestamp:        number;
  gasLimit:         number;
  gasUsed:          number;
  transactions:     string[] | Transaction[];
  size:             number;
  difficulty:       string;
  totalDifficulty:  string;
}

export interface Transaction {
  hash:             string;
  from:             string;
  to:               string | null;
  value:            bigint;
  gas:              number;
  gasPrice:         bigint;
  nonce:            number;
  input:            string;
  blockHash:        string | null;
  blockNumber:      number | null;
  transactionIndex: number | null;
  type:             string;
  status?:          'pending' | 'confirmed' | 'failed';
}

export interface TransactionReceipt {
  transactionHash:   string;
  transactionIndex:  number;
  blockHash:         string;
  blockNumber:       number;
  from:              string;
  to:                string | null;
  gasUsed:           number;
  cumulativeGasUsed: number;
  contractAddress:   string | null;
  logs:              Log[];
  status:            '0x0' | '0x1';
}

export interface Log {
  address:          string;
  topics:           string[];
  data:             string;
  blockNumber:      number;
  transactionHash:  string;
  transactionIndex: number;
  blockHash:        string;
  logIndex:         number;
  removed:          boolean;
}

export interface ValidatorInfo {
  address: string;
  status:  string;
  index:   number;
}

export interface ValidatorSet {
  validators: ValidatorInfo[];
  count:      number;
  epoch:      number;
  chainId:    number;
}

export interface NodeInfo {
  nodeType:    string;
  version:     string;
  chainId:     number;
  blockHeight: number;
  peers:       number;
}

export interface SyncStatus {
  syncing:          boolean;
  startingBlock?:   number;
  currentBlock?:    number;
  highestBlock?:    number;
}

export type Quantity = string;   // 0x-prefixed hex
export type HexData  = string;   // 0x-prefixed hex data

export interface RPCRequest {
  jsonrpc: '2.0';
  method:  string;
  params:  unknown[];
  id:      number;
}

export interface RPCResponse<T = unknown> {
  jsonrpc: '2.0';
  id:      number;
  result?: T;
  error?:  { code: number; message: string };
}
