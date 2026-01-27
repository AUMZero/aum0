import { Connection, PublicKey, TransactionInstruction } from '@solana/web3.js';
import BN from 'bn.js';
import { PROGRAM_ID } from './constants';
import { deriveProtocolState, deriveTokenScore } from './pda';
import { TokenScoreData, ScoreVerdict, SignalParams } from './types';

export class MeneiClient {
  private connection: Connection;
  private programId: PublicKey;

  constructor(connection: Connection, programId: PublicKey = PROGRAM_ID) {
    this.connection = connection;
    this.programId = programId;
  }

  async getProtocolState(): Promise<any> {
    const [pda] = deriveProtocolState();
    const info = await this.connection.getAccountInfo(pda);
    if (!info) return null;
    return this.deserializeProtocolState(info.data);
  }

  async getTokenScore(mint: PublicKey): Promise<TokenScoreData | null> {
    const [pda] = deriveTokenScore(mint);
    const info = await this.connection.getAccountInfo(pda);
    if (!info) return null;
    return this.deserializeTokenScore(info.data);
  }

  async getAllTokenScores(mints: PublicKey[]): Promise<Map<string, TokenScoreData>> {
    const results = new Map<string, TokenScoreData>();
    const pdas = mints.map((m) => deriveTokenScore(m)[0]);
    const infos = await this.connection.getMultipleAccountsInfo(pdas);

    for (let i = 0; i < mints.length; i++) {
      const info = infos[i];
      if (info) {
        results.set(mints[i].toBase58(), this.deserializeTokenScore(info.data));
      }
    }
    return results;
  }

  private deserializeProtocolState(data: Buffer): any {
    const offset = 8; // discriminator
    return {
      authority: new PublicKey(data.subarray(offset, offset + 32)),
      oracle: new PublicKey(data.subarray(offset + 32, offset + 64)),
      totalSignals: new BN(data.subarray(offset + 64, offset + 72), 'le').toNumber(),
      totalTokensScored: new BN(data.subarray(offset + 72, offset + 80), 'le').toNumber(),
    };
  }

  private deserializeTokenScore(data: Buffer): TokenScoreData {
    const offset = 8;
    return {
      mint: new PublicKey(data.subarray(offset, offset + 32)),
      score: data.readUInt16LE(offset + 32),
      signalCount: data.readUInt32LE(offset + 34),
      lastUpdated: new BN(data.subarray(offset + 38, offset + 46), 'le'),
      bondingProgress: data.readUInt16LE(offset + 46),
      socialFlags: data[offset + 48],
      verdict: data[offset + 49] as ScoreVerdict,
      confidence: data[offset + 50],
    };
  }
}
// updated: 2026-03-02

// TODO: add batch query support for multiple tokens


// batch










