import { PublicKey } from '@solana/web3.js';
import { deriveProtocolState, deriveTokenScore } from './pda';
import { PROGRAM_ID, MAX_SCORE } from './constants';
import { ScoreVerdict } from './types';

describe('PDA derivation', () => {
  test('deriveProtocolState returns consistent PDA', () => {
    const [pda1, bump1] = deriveProtocolState();
    const [pda2, bump2] = deriveProtocolState();
    expect(pda1.toBase58()).toBe(pda2.toBase58());
    expect(bump1).toBe(bump2);
    expect(PublicKey.isOnCurve(pda1)).toBe(false);
  });

  test('deriveTokenScore returns unique PDAs per mint', () => {
    const mintA = PublicKey.unique();
    const mintB = PublicKey.unique();
    const [pdaA] = deriveTokenScore(mintA);
    const [pdaB] = deriveTokenScore(mintB);
    expect(pdaA.toBase58()).not.toBe(pdaB.toBase58());
