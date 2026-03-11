# menei

![banner](./assets/banner.png)

**On-chain token intelligence protocol for Solana.** Real-time threat detection engine that combines multi-signal heuristic analysis with zero-copy on-chain state to produce cryptographically verifiable token risk scores.

Two programs. Five-stage analysis pipeline. Sub-second verdict latency.

---

### Architecture

```mermaid
flowchart TB
    subgraph ingestion["Event Ingestion Layer"]
        HS["Helius gRPC Stream"]
        WS["WebSocket Listener"]
        TP["Transaction Parser"]
        BF["Bloom Filter Dedup"]
        HS --> WS --> TP --> BF
    end

    subgraph extraction["Feature Extraction Pipeline"]
        direction LR
        P1["Pass 1<br/>Bonding Curve<br/>Analysis"]
        P2["Pass 2<br/>Holder Entropy<br/>Scoring"]
        P3["Pass 3<br/>Volume EWMA<br/>Detection"]
        P4["Pass 4<br/>Social Graph<br/>Mapping"]
        P5["Pass 5<br/>Creator<br/>Fingerprint"]
    end

    subgraph aggregator["Ensemble Aggregator"]
        WM["Adaptive Weight Matrix"]
        BC["Bayesian Confidence Scoring"]
        EP["Epoch-based Recalibration"]
        WM --> BC --> EP
    end

    subgraph onchain["On-Chain Settlement - Solana"]
        direction LR
        subgraph scoring["menei program"]
            SS["ScoringState PDA"]
            TV["TokenVerdict PDA"]
        end
        subgraph oracle["menei-oracle program"]
            FA["FeedAccount"]
            RB["Ring Buffer"]
        end
        oracle -- authenticated data feed --> scoring
    end

    ingestion --> extraction
    extraction --> aggregator
    aggregator -- zero-copy serialization --> onchain

    style ingestion fill:#0d1117,stroke:#58a6ff,stroke-width:2px,color:#c9d1d9
    style extraction fill:#0d1117,stroke:#3fb950,stroke-width:2px,color:#c9d1d9
    style aggregator fill:#0d1117,stroke:#d29922,stroke-width:2px,color:#c9d1d9
    style onchain fill:#0d1117,stroke:#f85149,stroke-width:2px,color:#c9d1d9
    style scoring fill:#161b22,stroke:#f85149,stroke-width:1px,color:#c9d1d9
    style oracle fill:#161b22,stroke:#f85149,stroke-width:1px,color:#c9d1d9
```

### How it works

The engine subscribes to Solana transaction streams via Helius gRPC and processes every pump.fun token creation event through a five-stage feature extraction pipeline:

1. **Ingestion** — low-latency WebSocket listener with automatic reconnection, backpressure handling, and deduplication via bloom filter
2. **Feature Extraction** — five parallel analysis passes:
   - *Bonding curve state analysis* — computes reserve ratio deviation, detects artificial liquidity injection patterns
   - *Holder entropy scoring* — Shannon entropy across top-N holders, Gini coefficient for concentration risk
   - *Volume EWMA* — exponentially weighted moving average with adaptive decay factor, detects wash trading via autocorrelation
   - *Social signal aggregation* — cross-references on-chain metadata with off-chain social graph topology
   - *Creator fingerprint* — behavioral clustering on deployer wallet history using Jaccard similarity over past token deployments
3. **Ensemble Aggregation** — adaptive weight matrix with per-signal Bayesian confidence intervals; weights are recalibrated every epoch based on prediction accuracy
4. **On-chain Settlement** — composite score + individual signal data written to PDAs using zero-copy serialization; oracle program provides authenticated external data feeds with staleness protection

Verdicts: `SKIP` (0–199) · `NEUTRAL` (200–499) · `WATCHING` (500–649) · `ALERT` (650+)

### Technical details

| Component | Implementation |
|-----------|---------------|
| On-chain programs | Anchor 0.29, zero-copy account deserialization, PDA-based state compression |
| Scoring model | Weighted ensemble with 5 orthogonal signal extractors, Bayesian confidence |
| Oracle | Permissioned feed with staleness guard, ECDSA-signed payloads |
| Data ingestion | Helius gRPC stream, bloom filter dedup, configurable backpressure |
| Weight calibration | Epoch-based recalibration using exponential decay on prediction residuals |
| State layout | Borsh-serialized, fixed-size accounts for O(1) access, rent-exempt PDAs |

### Quick start

```bash
git clone https://github.com/menei-ai/Menei.git && cd menei

# build programs
anchor build

# deploy to devnet
./scripts/deploy.sh devnet
./scripts/seed-oracle.sh devnet

# sdk
cd sdk && npm i && npm run build

# run engine
cd ../engine && cp .env.example .env   # configure RPC + keypair
npm i && npm start
```

Requires: Rust 1.75+, Solana CLI 1.17+, Anchor 0.29, Node 18+

### SDK

```typescript
import { Connection, PublicKey } from '@solana/web3.js';
import { MeneiClient } from '@menei/sdk';

const conn = new Connection('https://api.devnet.solana.com');
const client = new MeneiClient(conn);

const score = await client.getTokenScore(new PublicKey('...'));
// {
//   score: 847,
//   verdict: 'ALERT',
//   confidence: 0.92,
//   signals: {
//     bondingCurve: 0.12,
//     holderEntropy: 0.34,
//     volumeEWMA: 0.91,
//     socialScore: 0.78,
//     creatorRisk: 0.95
//   },
//   epoch: 1741,
//   timestamp: 1709251200
// }
```

### Project layout

```
programs/
  menei/                       on-chain scoring program (Anchor/Rust)
    src/
      instructions/            init, submit_signal, finalize, update_weights, withdraw
      state.rs                 account structs — ScoringState, TokenVerdict (zero-copy)
      errors.rs                typed error codes with anchor error macro
      events.rs                CPI event emission for off-chain indexers
      constants.rs             program-wide constants, PDA seeds, epoch config
  menei-oracle/                oracle data feed program
    src/
      processor/               register_feed, push_update, staleness guard
      state.rs                 FeedAccount with ring buffer for historical data
sdk/
  src/
    client.ts                  MeneiClient — getTokenScore, submitSignal, finalize
    pda.ts                     PDA derivation with seed hashing
    types.ts                   TypeScript type definitions mirroring on-chain structs
    constants.ts               program IDs, default config
engine/
  src/
    scanner.ts                 Helius gRPC stream consumer, bloom filter dedup
    analyzer.ts                five-pass feature extraction pipeline
    aggregator.ts              ensemble scoring with adaptive weight matrix
    config.ts                  environment config with validation
scripts/
    deploy.sh                  anchor deploy wrapper with IDL upload
    seed-oracle.sh             oracle feed initialization
```

### License

MIT — see [LICENSE](./LICENSE)
