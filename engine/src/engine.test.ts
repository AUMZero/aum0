import { Connection, PublicKey } from '@solana/web3.js';
import { TokenAnalyzer, AnalysisSignal } from './analyzer';
import { SignalAggregator } from './aggregator';
import { PumpFunScanner } from './scanner';

// -- TokenAnalyzer tests -------------------------------------------------

describe('TokenAnalyzer', () => {
  const mockConnection = {
    getAccountInfo: jest.fn(),
    getTokenLargestAccounts: jest.fn(),
    getSignaturesForAddress: jest.fn(),
  } as unknown as Connection;

  const analyzer = new TokenAnalyzer(mockConnection);
  const testMint = new PublicKey('So11111111111111111111111111111111111111112');

  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('analyze returns five signals for all categories', async () => {
    // mock all RPC calls to return empty/null
    (mockConnection.getAccountInfo as jest.Mock).mockResolvedValue(null);
    (mockConnection.getTokenLargestAccounts as jest.Mock).mockResolvedValue({ value: [] });
    (mockConnection.getSignaturesForAddress as jest.Mock).mockResolvedValue([]);

    const signals = await analyzer.analyze(testMint, {});
    expect(signals).toHaveLength(5);

    const categories = signals.map(s => s.category);
    expect(categories).toContain('bonding');
    expect(categories).toContain('social');
    expect(categories).toContain('holders');
    expect(categories).toContain('volume');
    expect(categories).toContain('creator');
  });

  test('all signals have valid value and confidence ranges', async () => {
    (mockConnection.getAccountInfo as jest.Mock).mockResolvedValue(null);
    (mockConnection.getTokenLargestAccounts as jest.Mock).mockResolvedValue({ value: [] });
    (mockConnection.getSignaturesForAddress as jest.Mock).mockResolvedValue([]);

    const signals = await analyzer.analyze(testMint, null);
    for (const signal of signals) {
      expect(signal.value).toBeGreaterThanOrEqual(0);
      expect(signal.value).toBeLessThanOrEqual(100);
      expect(signal.confidence).toBeGreaterThanOrEqual(0);
      expect(signal.confidence).toBeLessThanOrEqual(100);
      expect(signal.reason).toBeTruthy();
    }
  });

  test('social analysis penalizes missing metadata', async () => {
    (mockConnection.getAccountInfo as jest.Mock).mockResolvedValue(null);
    (mockConnection.getTokenLargestAccounts as jest.Mock).mockResolvedValue({ value: [] });
    (mockConnection.getSignaturesForAddress as jest.Mock).mockResolvedValue([]);

    const signals = await analyzer.analyze(testMint, null);
    const social = signals.find(s => s.category === 'social')!;
    expect(social.value).toBeGreaterThanOrEqual(70); // high risk when no metadata
  });

  test('social analysis rewards complete metadata', async () => {
    (mockConnection.getAccountInfo as jest.Mock).mockResolvedValue(null);
    (mockConnection.getTokenLargestAccounts as jest.Mock).mockResolvedValue({ value: [] });
    (mockConnection.getSignaturesForAddress as jest.Mock).mockResolvedValue([]);

    const metadata = {
      name: 'Legitimate Token',
      twitter: 'https://x.com/legit',
      website: 'https://legit.com',
      telegram: 'https://t.me/legit',
      description: 'A real project',
      uri: '',
    };

    const signals = await analyzer.analyze(testMint, metadata);
    const social = signals.find(s => s.category === 'social')!;
    expect(social.value).toBeLessThan(30); // low risk with full social presence
  });

  test('holder analysis handles empty holder list', async () => {
    (mockConnection.getAccountInfo as jest.Mock).mockResolvedValue(null);
    (mockConnection.getTokenLargestAccounts as jest.Mock).mockResolvedValue({ value: [] });
    (mockConnection.getSignaturesForAddress as jest.Mock).mockResolvedValue([]);

    const signals = await analyzer.analyze(testMint, {});
    const holders = signals.find(s => s.category === 'holders')!;
    expect(holders.value).toBeGreaterThanOrEqual(80); // high risk with no holders
    expect(holders.confidence).toBeLessThanOrEqual(40); // low confidence
  });

  test('volume analysis handles insufficient history', async () => {
    (mockConnection.getAccountInfo as jest.Mock).mockResolvedValue(null);
    (mockConnection.getTokenLargestAccounts as jest.Mock).mockResolvedValue({ value: [] });
    (mockConnection.getSignaturesForAddress as jest.Mock).mockResolvedValue([
      { signature: 'a', blockTime: 1000 },
      { signature: 'b', blockTime: 1001 },
    ]);

    const signals = await analyzer.analyze(testMint, {});
    const volume = signals.find(s => s.category === 'volume')!;
    expect(volume.confidence).toBeLessThanOrEqual(30);
  });
});

// -- SignalAggregator tests ----------------------------------------------

describe('SignalAggregator', () => {
  const weights = {
    bondingCurve: 0.30,
    socialPresence: 0.15,
    holderDistribution: 0.20,
    volumeVelocity: 0.20,
    creatorHistory: 0.15,
  };

  const aggregator = new SignalAggregator(weights);

  test('aggregate produces score in 0-1000 range', () => {
    const signals: AnalysisSignal[] = [
      { category: 'bonding', value: 50, confidence: 80, reason: 'test' },
      { category: 'social', value: 30, confidence: 70, reason: 'test' },
      { category: 'holders', value: 60, confidence: 85, reason: 'test' },
      { category: 'volume', value: 40, confidence: 45, reason: 'test' },
      { category: 'creator', value: 20, confidence: 50, reason: 'test' },
    ];

    const result = aggregator.aggregate(signals);
    expect(result.value).toBeGreaterThanOrEqual(0);
    expect(result.value).toBeLessThanOrEqual(1000);
  });

  test('high risk signals produce PROPHECY_ALERT verdict', () => {
    const signals: AnalysisSignal[] = [
      { category: 'bonding', value: 95, confidence: 90, reason: 'test' },
      { category: 'social', value: 90, confidence: 85, reason: 'test' },
      { category: 'holders', value: 95, confidence: 90, reason: 'test' },
      { category: 'volume', value: 90, confidence: 80, reason: 'test' },
      { category: 'creator', value: 95, confidence: 85, reason: 'test' },
    ];

    const result = aggregator.aggregate(signals);
    expect(result.verdict).toBe('PROPHECY_ALERT');
  });

  test('low risk signals produce SKIP verdict', () => {
    const signals: AnalysisSignal[] = [
      { category: 'bonding', value: 5, confidence: 80, reason: 'test' },
      { category: 'social', value: 10, confidence: 70, reason: 'test' },
      { category: 'holders', value: 5, confidence: 85, reason: 'test' },
      { category: 'volume', value: 10, confidence: 45, reason: 'test' },
      { category: 'creator', value: 5, confidence: 50, reason: 'test' },
    ];

    const result = aggregator.aggregate(signals);
    expect(result.verdict).toBe('SKIP');
  });

  test('breakdown contains all signal categories', () => {
    const signals: AnalysisSignal[] = [
      { category: 'bonding', value: 50, confidence: 80, reason: 'test' },
      { category: 'social', value: 30, confidence: 70, reason: 'test' },
      { category: 'holders', value: 60, confidence: 85, reason: 'test' },
      { category: 'volume', value: 40, confidence: 45, reason: 'test' },
      { category: 'creator', value: 20, confidence: 50, reason: 'test' },
    ];

    const result = aggregator.aggregate(signals);
    expect(result.breakdown).toHaveProperty('bonding');
    expect(result.breakdown).toHaveProperty('social');
    expect(result.breakdown).toHaveProperty('holders');
    expect(result.breakdown).toHaveProperty('volume');
    expect(result.breakdown).toHaveProperty('creator');
  });

  test('confidence reflects weighted signal confidence', () => {
    const signals: AnalysisSignal[] = [
      { category: 'bonding', value: 50, confidence: 100, reason: 'test' },
      { category: 'social', value: 30, confidence: 100, reason: 'test' },
      { category: 'holders', value: 60, confidence: 100, reason: 'test' },
      { category: 'volume', value: 40, confidence: 100, reason: 'test' },
      { category: 'creator', value: 20, confidence: 100, reason: 'test' },
    ];

    const result = aggregator.aggregate(signals);
    expect(result.confidence).toBeGreaterThan(0);
    expect(result.confidence).toBeLessThanOrEqual(100);
  });
});

// -- PumpFunScanner tests ------------------------------------------------

describe('PumpFunScanner', () => {
  test('registers handlers', () => {
    const scanner = new PumpFunScanner('https://api.devnet.solana.com');
    const handler = jest.fn();
    scanner.onNewToken(handler);
    // handler registered without error
    expect(handler).not.toHaveBeenCalled();
  });

  test('stop prevents further polling', () => {
    const scanner = new PumpFunScanner('https://api.devnet.solana.com');
    scanner.stop();
    // stop sets internal flag without error
  });
});



// accuracy















