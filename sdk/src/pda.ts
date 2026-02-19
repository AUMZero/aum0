import { PublicKey } from '@solana/web3.js';
import { PROGRAM_ID, PROTOCOL_SEED, TOKEN_SCORE_SEED } from './constants';

export function deriveProtocolState(): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(
    [PROTOCOL_SEED],
    PROGRAM_ID
  );
}

