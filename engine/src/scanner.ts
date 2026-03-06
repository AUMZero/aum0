// Helius websocket scanner for pump.fun token creation events
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
        console.error('[scanner] poll error:', e);
      }
      await new Promise(r => setTimeout(r, 2000));
    }
  }

  private async poll() {
    // placeholder: in production, fetches recent pump.fun program transactions
    // and extracts new token mints from InitializeMint instructions
  }
}
// updated: 2026-03-07
