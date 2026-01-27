// PDA derivation helpers for menei program accounts
import { PublicKey } from '@solana/web3.js';
import { PROGRAM_ID, PROTOCOL_SEED, TOKEN_SCORE_SEED } from './constants';

export function deriveProtocolState(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [PROTOCOL_SEED],
    PROGRAM_ID
  );
}

export function deriveTokenScore(mint: PublicKey): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [TOKEN_SCORE_SEED, mint.toBuffer()],
    PROGRAM_ID
  );
}
// updated: 2026-02-09

// seed



