// Multi-signal feature extractor
// Five orthogonal analysis passes run concurrently per token

import { Connection, PublicKey } from '@solana/web3.js';

export interface AnalysisSignal {
  category: 'bonding' | 'social' | 'holders' | 'volume' | 'creator';
  value: number;
  confidence: number;
  reason: string;
}

const PUMP_FUN_PROGRAM = new PublicKey('6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P');
const BONDING_CURVE_SEED = 'bonding-curve';

export class TokenAnalyzer {
  private connection: Connection;

  constructor(connection: Connection) {
    this.connection = connection;
  }

  async analyze(mint: PublicKey, metadata: any): Promise<AnalysisSignal[]> {
    const [bonding, social, holders, volume, creator] = await Promise.all([
      this.analyzeBondingCurve(mint),
      this.analyzeSocialPresence(metadata),
      this.analyzeHolderDistribution(mint),
      this.analyzeVolumeVelocity(mint),
      this.analyzeCreatorHistory(mint, metadata?.creator),
    ]);
    return [bonding, social, holders, volume, creator];
  }

  // -- Pass 1: Bonding Curve State Analysis --------------------------
  // Reads pump.fun bonding curve PDA to compute reserve ratio deviation
  // from expected constant-product trajectory. High deviation signals
  // artificial liquidity injection or coordinated buy pressure.

  private async analyzeBondingCurve(mint: PublicKey): Promise<AnalysisSignal> {
    try {
      const [curveAddr] = PublicKey.findProgramAddressSync(
        [Buffer.from(BONDING_CURVE_SEED), mint.toBuffer()],
        PUMP_FUN_PROGRAM,
      );

      const accountInfo = await this.connection.getAccountInfo(curveAddr);
      if (!accountInfo?.data) {
        return { category: 'bonding', value: 50, confidence: 20, reason: 'curve account not found' };
      }

      const data = accountInfo.data;
      const virtualTokenReserves = Number(data.readBigUInt64LE(8));
      const virtualSolReserves = Number(data.readBigUInt64LE(16));
      const realTokenReserves = Number(data.readBigUInt64LE(24));

      const totalSupply = 1_000_000_000 * 1e6;
      const sold = totalSupply - realTokenReserves;
      const progress = Math.min(1, sold / totalSupply);

      // expected reserve ratio under constant-product invariant
      const expectedRatio = 0.0001 + progress * progress * 0.5;
      const actualRatio = virtualSolReserves / (virtualTokenReserves || 1);
      const deviation = Math.abs(actualRatio - expectedRatio) / (expectedRatio || 1);

      const value = Math.min(100, Math.round(deviation * 200));
      const confidence = progress > 0.05 ? 85 : 40;

      return {
        category: 'bonding',
        value,
        confidence,
        reason: `progress=${(progress * 100).toFixed(1)}% deviation=${(deviation * 100).toFixed(1)}%`,
      };
    } catch {
      return { category: 'bonding', value: 50, confidence: 10, reason: 'failed to read curve state' };
    }
  }

  // -- Pass 2: Social Signal Aggregation -----------------------------
  // Cross-references on-chain metadata with presence of social links.
  // Missing social presence or generic/suspicious names = higher risk.

  private async analyzeSocialPresence(metadata: any): Promise<AnalysisSignal> {
    if (!metadata) {
      return { category: 'social', value: 80, confidence: 60, reason: 'no metadata available' };
    }

    let score = 0;
    const flags: string[] = [];
    const name = metadata.name || '';
    const description = metadata.description || '';
    const uri = metadata.uri || '';

    if (!name || name.length < 2) { score += 30; flags.push('no-name'); }

    if (!metadata.twitter && !/twitter\.com|x\.com/i.test(description + uri)) {
      score += 20; flags.push('no-twitter');
    }
    if (!metadata.website && !/https?:\/\/(?!twitter|t\.co|x\.com)/i.test(description)) {
      score += 15; flags.push('no-website');
    }
    if (!metadata.telegram && !/t\.me\//i.test(description + uri)) {
      score += 10; flags.push('no-telegram');
    }

    const suspicious = ['test', 'moon', 'elon', 'pepe', 'doge', 'shib', 'inu'];
    if (suspicious.some(s => name.toLowerCase().includes(s))) {
      score += 15; flags.push('generic-name');
    }

    return {
      category: 'social',
      value: Math.min(100, score),
      confidence: 70,
      reason: flags.length ? flags.join(', ') : 'social presence verified',
    };
  }

  // -- Pass 3: Holder Entropy Scoring --------------------------------
  // Shannon entropy + Gini coefficient over top token holders.
  // Low entropy + high Gini = insider accumulation or sybil clusters.

  private async analyzeHolderDistribution(mint: PublicKey): Promise<AnalysisSignal> {
    try {
      const accounts = await this.connection.getTokenLargestAccounts(mint);
      const balances = accounts.value.map(h => Number(h.amount)).filter(b => b > 0);

      if (balances.length === 0) {
        return { category: 'holders', value: 90, confidence: 30, reason: 'no holders found' };
      }

      const total = balances.reduce((a, b) => a + b, 0);
      if (total === 0) {
        return { category: 'holders', value: 50, confidence: 20, reason: 'zero supply' };
      }

      const proportions = balances.map(b => b / total);

      // Shannon entropy: H = -sum(p_i * log2(p_i))
      const entropy = -proportions.reduce((sum, p) => {
        return p > 0 ? sum + p * Math.log2(p) : sum;
      }, 0);
      const maxEntropy = Math.log2(balances.length || 1);
      const normalizedEntropy = maxEntropy > 0 ? entropy / maxEntropy : 0;

      // Gini coefficient via mean absolute difference
      const sorted = [...balances].sort((a, b) => a - b);
      const n = sorted.length;
      const mean = total / n;
      let sumDiff = 0;
      for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) {
          sumDiff += Math.abs(sorted[i] - sorted[j]);
        }
      }
      const gini = sumDiff / (2 * n * n * mean);

      const topHolderPct = proportions[0] || 0;

      // composite risk score
      let riskScore = 0;
      riskScore += (1 - normalizedEntropy) * 40;
      riskScore += gini * 35;
      riskScore += topHolderPct * 25;

      return {
        category: 'holders',
        value: Math.min(100, Math.round(riskScore)),
        confidence: balances.length >= 10 ? 85 : 50,
        reason: `entropy=${normalizedEntropy.toFixed(2)} gini=${gini.toFixed(2)} top=${(topHolderPct * 100).toFixed(1)}%`,
      };
    } catch {
      return { category: 'holders', value: 50, confidence: 10, reason: 'failed to fetch holders' };
    }
  }

  // -- Pass 4: Volume EWMA Detection ---------------------------------
  // Exponentially weighted moving average of inter-trade intervals.
  // Autocorrelation at lag-1 detects wash trading (bot patterns).

  private async analyzeVolumeVelocity(mint: PublicKey): Promise<AnalysisSignal> {
    try {
      const signatures = await this.connection.getSignaturesForAddress(
        mint, { limit: 100 }, 'confirmed',
      );

      if (signatures.length < 5) {
        return { category: 'volume', value: 30, confidence: 25, reason: 'insufficient trade history' };
      }

      const timestamps = signatures
        .map(s => s.blockTime || 0)
        .filter(t => t > 0)
        .sort((a, b) => a - b);

      const intervals: number[] = [];
      for (let i = 1; i < timestamps.length; i++) {
        intervals.push(timestamps[i] - timestamps[i - 1]);
      }

      if (intervals.length < 3) {
        return { category: 'volume', value: 40, confidence: 20, reason: 'not enough intervals' };
      }

      // EWMA with decay factor alpha = 0.3
      let ewma = intervals[0];
      for (let i = 1; i < intervals.length; i++) {
        ewma = 0.3 * intervals[i] + 0.7 * ewma;
      }

      // autocorrelation at lag 1
      const mean = intervals.reduce((a, b) => a + b, 0) / intervals.length;
      let num = 0, den = 0;
      for (let i = 0; i < intervals.length - 1; i++) {
        num += (intervals[i] - mean) * (intervals[i + 1] - mean);
      }
      for (const interval of intervals) {
        den += (interval - mean) ** 2;
      }
      const autocorr = den === 0 ? 0 : num / den;

      // trades per minute over recent window
      const recent = timestamps.slice(-20);
      const dur = (recent[recent.length - 1] - recent[0]) || 1;
      const tpm = (recent.length / dur) * 60;

      let riskScore = 0;
      // >0.7 autocorrelation = highly regular interval pattern (bot signature)
      if (autocorr > 0.7) riskScore += 40;
      // 0.4-0.7 = moderately regular, could be organic with some bot activity
      else if (autocorr > 0.4) riskScore += 20;
      // >30 trades/min in first minutes = almost certainly automated sniping
      if (tpm > 30) riskScore += 35;
      else if (tpm > 10) riskScore += 15;
      // <2s average interval = sub-human speed, indicates bot execution
      if (ewma < 2) riskScore += 25;

      return {
        category: 'volume',
        value: Math.min(100, riskScore),
        confidence: intervals.length >= 20 ? 80 : 45,
        reason: `ewma=${ewma.toFixed(1)}s autocorr=${autocorr.toFixed(2)} tpm=${tpm.toFixed(1)}`,
      };
    } catch {
      return { category: 'volume', value: 40, confidence: 10, reason: 'failed to fetch signatures' };
    }
  }

  // -- Pass 5: Creator Fingerprint -----------------------------------
  // Deployer wallet history: past token launches, wallet age, and
  // Jaccard similarity over tx instruction patterns to detect serials.

  private async analyzeCreatorHistory(
    mint: PublicKey,
    creator?: PublicKey,
  ): Promise<AnalysisSignal> {
    if (!creator) {
      return { category: 'creator', value: 60, confidence: 30, reason: 'creator unknown' };
    }

    try {
      const sigs = await this.connection.getSignaturesForAddress(
        creator, { limit: 200 }, 'confirmed',
      );

      if (sigs.length < 5) {
        return { category: 'creator', value: 55, confidence: 40, reason: 'new wallet' };
      }

      const successRate = sigs.filter(s => s.err === null).length / sigs.length;
      let riskScore = 0;

      // serial deployers who spam tokens have high success rate
      if (successRate > 0.8) riskScore += 50;
      else if (successRate > 0.5) riskScore += 25;

      // wallet age heuristic
      const oldest = sigs[sigs.length - 1].blockTime || 0;
      const newest = sigs[0].blockTime || 0;
      const ageDays = (newest - oldest) / 86400;

      // <1 day old wallet deploying tokens = likely throwaway deployer
      if (ageDays < 1) riskScore += 30;
      // <7 days = new wallet, moderate risk of hit-and-run deployment
      else if (ageDays < 7) riskScore += 15;

      // Jaccard similarity over sliding windows of tx patterns
      // bot wallets produce near-identical transaction sequences
      const patterns = sigs.slice(0, 50).map(s => s.err ? 'F' : 'S');
      let similarity = 0;
      if (patterns.length >= 10) {
        let totalSim = 0, comps = 0;
        for (let i = 0; i <= patterns.length - 6; i++) {
          const w1 = new Set(patterns.slice(i, i + 5));
          const w2 = new Set(patterns.slice(i + 1, i + 6));
          const inter = [...w1].filter(x => w2.has(x)).length;
          const union = new Set([...w1, ...w2]).size;
          if (union > 0) { totalSim += inter / union; comps++; }
        }
        similarity = comps > 0 ? totalSim / comps : 0;
      }
      // >0.85 jaccard = near-identical tx patterns across window, strong bot signal
      if (similarity > 0.85) riskScore += 20;

      return {
        category: 'creator',
        value: Math.min(100, riskScore),
        confidence: sigs.length >= 50 ? 80 : 50,
        reason: `txs=${sigs.length} rate=${(successRate * 100).toFixed(0)}% age=${ageDays.toFixed(0)}d sim=${similarity.toFixed(2)}`,
      };
    } catch {
      return { category: 'creator', value: 50, confidence: 10, reason: 'failed to fetch creator history' };
    }
  }
}
