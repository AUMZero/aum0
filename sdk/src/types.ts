import { PublicKey } from '@solana/web3.js';
import BN from 'bn.js';

export enum ScoreVerdict {
  Skip = 0,
  Neutral = 1,
  Watching = 2,
  ProphecyAlert = 3,
}

export interface TokenScoreData {
  mint: PublicKey;
  score: number;
  signalCount: number;
  lastUpdated: BN;
  bondingProgress: number;
  socialFlags: number;
  verdict: ScoreVerdict;
  confidence: number;
}

export interface SignalParams {
  tokenMint: PublicKey;
  scoreDelta: number;
  bondingProgress: number;
  socialFlags: number;
  confidence: number;
}

export interface ProtocolConfig {
  feeBasisPoints: number;
  oracle: PublicKey;
}
