import { PublicKey } from '@solana/web3.js';

export const PROGRAM_ID = new PublicKey('MNEi8sBgZ2vFQLwb4HCPESKgJjPaFNbfRwqEdHmw1HZ');
export const PROTOCOL_SEED = Buffer.from('protocol_state');
export const TOKEN_SCORE_SEED = Buffer.from('token_score');
export const MAX_SCORE = 1000;
export const FEE_DENOMINATOR = 10000;
// updated: 2026-03-01
