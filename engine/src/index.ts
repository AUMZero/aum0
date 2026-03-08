// Pipeline entry — scanner → analyzer → aggregator
import { TokenAnalyzer } from './analyzer';
import { SignalAggregator } from './aggregator';
import { PumpFunScanner } from './scanner';
import { config } from './config';

async function main() {
  const scanner = new PumpFunScanner(config.rpcUrl);
  const analyzer = new TokenAnalyzer();
  const aggregator = new SignalAggregator(config.weights);

  console.log('[engine] starting token scanner...');

  scanner.onNewToken(async (mint, metadata) => {
    const signals = await analyzer.analyze(mint, metadata);
    const score = aggregator.aggregate(signals);

    console.log(`[engine] ${mint.toBase58().slice(0, 8)}... score=${score.value} verdict=${score.verdict}`);

    if (score.verdict === 'PROPHECY_ALERT') {
      console.log(`[engine] !!! HIGH CONFIDENCE DETECTION: ${mint.toBase58()}`);
    }
  });

  await scanner.start();
}

main().catch(console.error);
// updated: 2026-02-14

// TODO: add prometheus metrics endpoint for monitoring
