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
