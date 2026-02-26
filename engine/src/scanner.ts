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

  constructor(rpcUrl: string) {
    this.connection = new Connection(rpcUrl, 'confirmed');
  }

  onNewToken(handler: (mint: PublicKey, meta: TokenMetadata) => Promise<void>) {
    this.handlers.push(handler);
  }

  async start() {
    console.log('[scanner] watching for new pump.fun tokens...');
    // poll loop — in production this would use websocket subscription
    while (true) {
      try {
        await this.poll();
      } catch (e) {
