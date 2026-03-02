import { AnalysisSignal } from './analyzer';

interface Weights {
  bondingCurve: number;
  socialPresence: number;
  holderDistribution: number;
  volumeVelocity: number;
  creatorHistory: number;
}

interface AggregatedScore {
  value: number;
  verdict: 'SKIP' | 'NEUTRAL' | 'WATCHING' | 'PROPHECY_ALERT';
  confidence: number;
  breakdown: Record<string, number>;
}

const WEIGHT_MAP: Record<string, keyof Weights> = {
  bonding: 'bondingCurve',
  social: 'socialPresence',
  holders: 'holderDistribution',
  volume: 'volumeVelocity',
  creator: 'creatorHistory',
};

export class SignalAggregator {
  private weights: Weights;

  constructor(weights: Weights) {
    this.weights = weights;
  }

  aggregate(signals: AnalysisSignal[]): AggregatedScore {
    let totalScore = 0;
    let totalConfidence = 0;
    const breakdown: Record<string, number> = {};

    for (const signal of signals) {
      const weightKey = WEIGHT_MAP[signal.category];
      if (!weightKey) continue;
