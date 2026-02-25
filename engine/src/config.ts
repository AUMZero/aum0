import { config as dotenvConfig } from 'dotenv';
dotenvConfig();

export const config = {
  rpcUrl: process.env.RPC_URL || 'https://api.mainnet-beta.solana.com',
  scanIntervalMs: Number(process.env.SCAN_INTERVAL_MS) || 2000,
  weights: {
    bondingCurve: 0.30,
    socialPresence: 0.15,
    holderDistribution: 0.20,
    volumeVelocity: 0.20,
    creatorHistory: 0.15,
  },
  thresholds: {
    skip: 250,
    neutral: 450,
    watching: 650,
    prophecyAlert: 800,
  },
};
// updated: 2026-02-11
