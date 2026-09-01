// The employee's hands. Polls the chain, finds accounts off their law,
// rebalances them across every asset in the venue, earns the bounty.
// Serves every AUM0 venue listed in CONTRACTS. Runs when KEEPER_PK is set.
import { JsonRpcProvider, FetchRequest, Wallet, Contract } from 'ethers';

const RPC = process.env.RPC_URL || 'https://rpc.mainnet.chain.robinhood.com';
const CONTRACTS = [
  { addr: '0xaFd484733f4B23e235bf1825c9AdA39368160B03', fromBlock: 50946000, wallet: true },  // v3: assets stay in the owner's wallet
  { addr: '0xcc27Dd6FD74210303660643bcf6c9d115443bFcA', fromBlock: 50820000 },                // custody, 15 stocks
  { addr: '0xE46B6e60c7b2CbC1f9761B3f12a69813093B6dde', fromBlock: 50600000 },                // custody, NVDA only
];
const POLL_MS = 60_000;
const MIN_ACT_BPS = 300;      // don't grind dust: act only on real drift
const MIN_VALUE_USD = 0.5;    // ignore empty accounts
const MIN_LEG_USD = 0.05;     // skip legs the pool fee would eat
const MAX_TX_PER_DAY = 200;   // hard spend cap
const DRY = process.env.DRY_RUN === '1';

const ABI = [
  'function accountOf(address) view returns (uint16[] targetBps, uint16 minDriftBps, uint16 bandBps, uint128 bountyQuote)',
  'function valueOf(address) view returns (uint256)',
  'function drift(address) view returns (uint256)',
  'function balanceOf(address, uint256) view returns (uint256)',
  'function heldBy(address, uint256) view returns (uint256)',
  'function assetCount() view returns (uint256)',
  'function assetAt(uint256) view returns (address token, address feed, uint24 poolFee, uint8 decimals)',
  'function rebalance(address user, (uint256 sellAsset, uint256 buyAsset, uint256 amountIn)[] trades)',
  'event TargetSet(address indexed user, uint16[] targetBps, uint16 minDriftBps, uint16 bandBps, uint128 bountyQuote)',
];
const FEED_ABI = ['function latestRoundData() view returns (uint80, int256, uint256, uint256, uint80)'];

const req = new FetchRequest(RPC);
req.setHeader('user-agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36');
const provider = new JsonRpcProvider(req, 4663, { staticNetwork: true });
let wallet;

let sentToday = 0, dayStamp = '';
const backoff = new Map(); // `${venue}:${user}` -> fail count

function log(...a) { console.log(new Date().toISOString(), '[keeper]', ...a); }

async function loadVenue(v) {
  v.c = new Contract(v.addr, ABI, wallet);
  const n = Number(await v.c.assetCount());
  v.assets = [];
  for (let i = 0; i < n; i++) {
    const a = await v.c.assetAt(i);
    v.assets.push({ feed: a.feed, decimals: Number(a.decimals), feedC: i === 0 ? null : new Contract(a.feed, FEED_ABI, provider) });
  }
  log(`venue ${v.addr.slice(0, 8)}… loaded, ${n} assets`);
}

async function prices(v) {
  const out = [1];
  for (let i = 1; i < v.assets.length; i++) {
    const [, p] = await v.assets[i].feedC.latestRoundData();
    out.push(Number(p) / 1e8);
  }
  return out;
}

// Sells first (they raise cash), then buys, each leg 3% inside the line.
function planTrades(weights, balances, px, cash) {
  const value = balances.reduce((s, b, i) => s + b * px[i], 0);
  if (value < MIN_VALUE_USD) return null;
  const sells = [], buys = [];
  let cashFreed = 0, cashNeeded = 0;
  for (let i = 1; i < balances.length; i++) {
    const delta = (value * Number(weights[i]) / 10000 - balances[i] * px[i]) * 0.97;
    if (delta < -MIN_LEG_USD) {
      sells.push({ sellAsset: BigInt(i), buyAsset: 0n, amountIn: BigInt(Math.floor(-delta / px[i] * 1e18)) });
      cashFreed += -delta;
    } else if (delta > MIN_LEG_USD) {
      buys.push({ sellAsset: 0n, buyAsset: BigInt(i), amountIn: BigInt(Math.floor(delta * 1e6)), usd: delta });
    }
  }
  // buys spend cash on hand plus what the sells free up (less pool fees)
  const budget = cash + cashFreed * 0.99;
  cashNeeded = buys.reduce((s, b) => s + b.usd, 0);
  if (cashNeeded > budget) {
    const k = budget / cashNeeded;
    for (const b of buys) b.amountIn = BigInt(Math.floor(Number(b.amountIn) * k));
  }
  const trades = [...sells, ...buys.map(({ usd, ...t }) => t)].filter(t => t.amountIn > 0n);
  return trades.length ? { trades, cashAfter: budget - Math.min(cashNeeded, budget) } : null;
}

async function serveOne(v, user, px) {
  const [acct, driftRaw] = await Promise.all([v.c.accountOf(user), v.c.drift(user).catch(() => null)]);
  if (driftRaw === null) return;
  const drift = Number(driftRaw);
  if (drift < Math.max(Number(acct.minDriftBps), MIN_ACT_BPS)) return;

  const balances = [];
  for (let i = 0; i < v.assets.length; i++) {
    const raw = v.wallet ? await v.c.heldBy(user, i) : await v.c.balanceOf(user, i);
    balances.push(Number(raw) / 10 ** (i === 0 ? 6 : 18));
  }
  const plan = planTrades(acct.targetBps, balances, px, balances[0]);
  if (!plan) return;

  const expectedPay = Number(acct.bountyQuote) / 1e6 * drift / 10000;
  if (expectedPay > plan.cashAfter) { log(user, 'skipped: bounty exceeds cash (broken policy)'); return; }

  if (DRY) { log(user, `DRY: drift ${drift}, ${plan.trades.length} legs, pay ~$${expectedPay.toFixed(2)}`); return; }

  const tx = await v.c.rebalance(user, plan.trades, { gasLimit: 600_000 + 400_000 * plan.trades.length });
  const rc = await tx.wait();
  sentToday++;
  log(user, `rebalanced on ${v.addr.slice(0, 8)}…. drift was ${drift}, ${plan.trades.length} legs, pay ~$${expectedPay.toFixed(2)}, gas ${rc.gasUsed}, tx ${tx.hash}`);
  backoff.delete(v.addr + ':' + user);
}

async function users(v) {
  const logs = await provider.getLogs({ address: v.addr, topics: [v.c.interface.getEvent('TargetSet').topicHash], fromBlock: v.fromBlock });
  return [...new Set(logs.map(l => '0x' + l.topics[1].slice(26)))];
}

async function tick() {
  const day = new Date().toISOString().slice(0, 10);
  if (day !== dayStamp) { dayStamp = day; sentToday = 0; }
  if (sentToday >= MAX_TX_PER_DAY) return log('daily tx cap reached, resting');
  for (const v of CONTRACTS) {
    const px = await prices(v);
    for (const u of await users(v)) {
      const key = v.addr + ':' + u;
      if ((backoff.get(key) || 0) >= 3) continue;
      try { await serveOne(v, u, px); }
      catch (e) {
        backoff.set(key, (backoff.get(key) || 0) + 1);
        log(u, 'failed:', String(e.shortMessage || e.message).slice(0, 120));
      }
    }
  }
}

export async function startKeeper() {
  if (!process.env.KEEPER_PK) { log('no KEEPER_PK, hands stay in pockets'); return; }
  wallet = new Wallet(process.env.KEEPER_PK, provider);
  for (const v of CONTRACTS) await loadVenue(v);
  log(`up. wallet ${wallet.address}, poll ${POLL_MS / 1000}s, act >= ${MIN_ACT_BPS} bps${DRY ? ', DRY RUN' : ''}`);
  const loop = () => tick().catch(e => log('tick failed:', String(e.message).slice(0, 120))).finally(() => setTimeout(loop, POLL_MS));
  loop();
}
