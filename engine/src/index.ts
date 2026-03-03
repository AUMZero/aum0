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
