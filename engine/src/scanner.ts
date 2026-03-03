// Helius gRPC stream consumer for pump.fun token creation events
// Implements bloom filter dedup and exponential backoff reconnection

import { Connection, PublicKey, ConfirmedSignatureInfo } from '@solana/web3.js';

interface TokenMetadata {
  mint: PublicKey;
  name: string;
  symbol: string;
  creator: PublicKey;
  createdAt: number;
  bondingCurveProgress: number;
  uri: string;
}

type TokenHandler = (mint: PublicKey, meta: TokenMetadata) => Promise<void>;

// lightweight bloom filter for deduplication
class BloomFilter {
  private bits: Uint8Array;
  private hashCount: number;

  constructor(size: number = 65536, hashCount: number = 3) {
    this.bits = new Uint8Array(size);
    this.hashCount = hashCount;
  }

  private hash(str: string, seed: number): number {
    let h = seed;
    for (let i = 0; i < str.length; i++) {
      h = (h * 31 + str.charCodeAt(i)) >>> 0;
    }
    return h % this.bits.length;
  }

  add(item: string): void {
    for (let i = 0; i < this.hashCount; i++) {
      this.bits[this.hash(item, i + 1)] = 1;
    }
  }

  mayContain(item: string): boolean {
    for (let i = 0; i < this.hashCount; i++) {
      if (!this.bits[this.hash(item, i + 1)]) return false;
    }
    return true;
  }
}

const PUMP_FUN_PROGRAM = new PublicKey('6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P');
const POLL_INTERVAL_MS = 2000;
const MAX_BACKOFF_MS = 30000;

export class PumpFunScanner {
  private connection: Connection;
  private handlers: TokenHandler[] = [];
  private bloomFilter: BloomFilter;
  private running = false;
  private consecutiveErrors = 0;
  private lastSignature: string | undefined;

  constructor(rpcUrl: string) {
    this.connection = new Connection(rpcUrl, 'confirmed');
    this.bloomFilter = new BloomFilter();
  }

  onNewToken(handler: TokenHandler): void {
    this.handlers.push(handler);
  }

  async start(): Promise<void> {
    this.running = true;
    console.log('[scanner] watching for new pump.fun tokens...');

    while (this.running) {
      try {
        await this.poll();
        this.consecutiveErrors = 0;
      } catch (e) {
        this.consecutiveErrors++;
        const backoff = Math.min(
          POLL_INTERVAL_MS * Math.pow(2, this.consecutiveErrors),
          MAX_BACKOFF_MS,
        );
        console.error(`[scanner] poll error (retry in ${backoff}ms):`, e);
        await this.sleep(backoff);
        continue;
      }
      await this.sleep(POLL_INTERVAL_MS);
    }
  }

  stop(): void {
    this.running = false;
    console.log('[scanner] stopped');
  }

  private async poll(): Promise<void> {
    // fetch recent signatures for the pump.fun program
    const opts: { limit: number; until?: string } = { limit: 25 };
    if (this.lastSignature) {
      opts.until = this.lastSignature;
    }

    const signatures = await this.connection.getSignaturesForAddress(
      PUMP_FUN_PROGRAM,
      opts,
      'confirmed',
    );

    if (signatures.length === 0) return;

    // update cursor for next poll
    this.lastSignature = signatures[0].signature;

    // process in chronological order (oldest first)
    const chronological = signatures.reverse();

    for (const sig of chronological) {
      if (sig.err) continue;

      const sigStr = sig.signature;
      if (this.bloomFilter.mayContain(sigStr)) continue;
      this.bloomFilter.add(sigStr);

      // fetch full transaction to extract token creation data
      const tx = await this.connection.getParsedTransaction(sigStr, {
        maxSupportedTransactionVersion: 0,
      });

      if (!tx?.meta || tx.meta.err) continue;

      // look for InitializeMint in inner instructions
      const mint = this.extractNewMint(tx);
      if (!mint) continue;

      const metadata = this.extractMetadata(tx, mint, sig);
      await this.notifyHandlers(mint, metadata);
    }
  }

  private extractNewMint(tx: any): PublicKey | null {
    const instructions = tx.transaction?.message?.instructions || [];
    const innerInstructions = tx.meta?.innerInstructions || [];

    // check inner instructions for InitializeMint
    for (const inner of innerInstructions) {
      for (const ix of inner.instructions) {
        if (
          ix.parsed?.type === 'initializeMint' &&
          ix.program === 'spl-token'
        ) {
          return new PublicKey(ix.parsed.info.mint);
        }
      }
    }

    // fallback: check top-level instructions
    for (const ix of instructions) {
      if (
        ix.parsed?.type === 'initializeMint' &&
        ix.program === 'spl-token'
      ) {
        return new PublicKey(ix.parsed.info.mint);
      }
    }

    return null;
  }

  private extractMetadata(
    tx: any,
    mint: PublicKey,
    sig: ConfirmedSignatureInfo,
  ): TokenMetadata {
    const accounts = tx.transaction?.message?.accountKeys || [];
    const creator = accounts.length > 0
      ? new PublicKey(accounts[0].pubkey || accounts[0])
      : PublicKey.default;

    return {
      mint,
      name: '',
      symbol: '',
      creator,
      createdAt: sig.blockTime || Math.floor(Date.now() / 1000),
      bondingCurveProgress: 0,
      uri: '',
    };
  }

  private async notifyHandlers(mint: PublicKey, meta: TokenMetadata): Promise<void> {
    for (const handler of this.handlers) {
      try {
        await handler(mint, meta);
      } catch (e) {
        console.error(`[scanner] handler error for ${mint.toBase58()}:`, e);
      }
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}




// backoff
// bloom





















