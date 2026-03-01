// Pipeline entry: scanner -> analyzer -> aggregator -> on-chain settlement
// Rate-limited to prevent RPC congestion on mainnet

import { Connection } from '@solana/web3.js';
import { TokenAnalyzer } from './analyzer';
import { SignalAggregator } from './aggregator';
import { PumpFunScanner } from './scanner';
import { config } from './config';

// token-level rate limiter: max N concurrent analyses
class RateLimiter {
  private active = 0;
  private queue: Array<() => void> = [];

  constructor(private maxConcurrent: number) {}

  async acquire(): Promise<void> {
    if (this.active < this.maxConcurrent) {
      this.active++;
      return;
    }
    return new Promise(resolve => this.queue.push(resolve));
  }

  release(): void {
    this.active--;
    const next = this.queue.shift();
    if (next) {
      this.active++;
      next();
    }
  }
}

async function main() {
  const connection = new Connection(config.rpcUrl, 'confirmed');
  const scanner = new PumpFunScanner(config.rpcUrl);
  const analyzer = new TokenAnalyzer(connection);
  const aggregator = new SignalAggregator(config.weights);

  // limit concurrent analyses to avoid RPC rate limits
  // 5 concurrent is safe for most RPC providers (Helius, QuickNode)
  const limiter = new RateLimiter(5);

  let processed = 0;
  let alerts = 0;

  console.log('[engine] starting menei token scanner...');
  console.log(`[engine] rpc: ${config.rpcUrl.slice(0, 30)}...`);
  console.log(`[engine] max concurrent analyses: 5`);

  scanner.onNewToken(async (mint, metadata) => {
    await limiter.acquire();
    try {
      const signals = await analyzer.analyze(mint, metadata);
      const score = aggregator.aggregate(signals);
      processed++;

      const mintStr = mint.toBase58().slice(0, 8);
      console.log(`[engine] ${mintStr}... score=${score.value} verdict=${score.verdict} (${processed} total)`);

      if (score.verdict === 'PROPHECY_ALERT') {
        alerts++;
        console.log(`[engine] !!! HIGH CONFIDENCE DETECTION: ${mint.toBase58()}`);
        console.log(`[engine]     breakdown: ${JSON.stringify(score.breakdown)}`);
        console.log(`[engine]     confidence: ${score.confidence}%`);
      }
    } finally {
      limiter.release();
    }
  });

  // graceful shutdown
  process.on('SIGINT', () => {
    console.log(`\n[engine] shutting down... processed=${processed} alerts=${alerts}`);
    scanner.stop();
    process.exit(0);
  });

  await scanner.start();
}

main().catch(console.error);












