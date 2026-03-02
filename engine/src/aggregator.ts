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
