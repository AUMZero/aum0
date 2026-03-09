# menei

![banner](./assets/banner.png)

Real-time token analysis engine for Solana. Scans pump.fun launches, runs heuristic scoring, writes verdicts on-chain.

Built with Anchor + TypeScript. Two on-chain programs + off-chain scanner.

---

### How it works

The engine polls pump.fun for new mints and runs a scoring pipeline:

1. **Scanner** picks up new token creation txs via Helius websocket
2. **Analyzer** extracts features — bonding curve state, holder concentration, volume patterns, social signals, creator history
3. **Aggregator** computes weighted score (0-1000) and maps to verdict
4. Result gets written to a PDA on Solana

Verdicts: `SKIP` (0-199) · `NEUTRAL` (200-499) · `WATCHING` (500-649) · `ALERT` (650+)

### Quick start

```bash
git clone https://github.com/menei-ai/Menei.git && cd menei

# programs
anchor build
./scripts/deploy.sh devnet

# sdk
cd sdk && npm i && npm run build

# engine
cd ../engine && npm i && npm start
```

Requires: Rust 1.75+, Solana CLI 1.17+, Anchor 0.29, Node 18+

### SDK usage

```typescript
import { Connection, PublicKey } from '@solana/web3.js';
import { MeneiClient } from '@menei/sdk';

const conn = new Connection('https://api.devnet.solana.com');
const client = new MeneiClient(conn);

const score = await client.getTokenScore(new PublicKey('...'));
console.log(score);
// { score: 847, verdict: 'ALERT', confidence: 92, signals: 4 }
```

### Project layout

```
programs/
  menei/src/          on-chain scoring program (Anchor/Rust)
    instructions/              init, submit_signal, finalize, update_weights, withdraw
    state.rs / errors.rs       account structs + error codes
  menei-oracle/src/   oracle data feed program
    processor/                 register_feed, submit_data, update_config
engine/src/                    off-chain analysis engine (TypeScript)
  scanner.ts                   pump.fun event poller
  analyzer.ts                  feature extraction (5 passes)
  aggregator.ts                weighted scoring + verdict
sdk/src/                       client SDK
  client.ts                    MeneiClient class
  pda.ts                       PDA derivation helpers
scripts/                       deploy + init scripts
```

### License

MIT — see [LICENSE](./LICENSE)
