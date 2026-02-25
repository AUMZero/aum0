import { Connection, PublicKey } from '@solana/web3.js';

interface TokenMetadata {
  mint: PublicKey;
  name: string;
  symbol: string;
  createdAt: number;
  bondingCurveProgress: number;
}

export class PumpFunScanner {
  private connection: Connection;
  private handlers: Array<(mint: PublicKey, meta: TokenMetadata) => Promise<void>> = [];
  private seenMints = new Set<string>();

