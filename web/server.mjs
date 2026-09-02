// aumzero.com: static site + Hood RPC proxy in one process.
// The public Hood RPC sits behind a bot filter that dislikes bare fetches,
// so the page talks through here with a plain browser identity.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { gzipSync } from 'node:zlib';

const PORT = process.env.PORT || 3000;
const ROOT = new URL('.', import.meta.url).pathname;
const UPSTREAM = 'https://rpc.mainnet.chain.robinhood.com';
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
// Only what the page needs; anything else is refused.
const ALLOW = new Set(['eth_call', 'eth_blockNumber', 'eth_getBalance', 'eth_chainId', 'eth_getLogs']);
const AUM0S = new Set(['0xe46b6e60c7b2cbc1f9761b3f12a69813093b6dde', '0xcc27dd6fd74210303660643bcf6c9d115443bfca', '0xafd484733f4b23e235bf1825c9ada39368160b03']);
// The proxy serves this site only. No CORS headers are ever emitted, so
// other origins cannot borrow it from a browser; same-origin needs none.
const SITE_ORIGINS = new Set(['https://aumzero.com', 'https://www.aumzero.com', 'https://aum0-web-production.up.railway.app', 'http://localhost:3000', 'http://127.0.0.1:3000']);

// Feed prices are the same for every visitor, so the server reads them once
// and hands out the cached copy. Fifteen calls per refresh instead of fifteen
// per person.
const FEEDS = [
  '0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15','0xB265810950ba6c5C0Ff821c9963014a56fD8Bffb',
  '0x4A1166a659A55625345e9515b32adECea5547C38','0x6B22A786bAa607d76728168703a39Ea9C99f2cD0',
  '0x45C3C877C15E6BA2EBB19eA114Ea508d14C1Af2E','0xD5a1508ceD74c084eBf3cBe853e2C968fB2a651C',
  '0x425EEFdCf05ed6526C3cE61Af99429A228a6d596','0x319724394D3A0e3669269846abE664Cd621f9f6A',
  '0x820ABedFF239034956B7A9d2F0a331f9F075eB4c','0xfb133Fa4B7b385802B693a293606682Df47109A3',
  '0x3f390C5C24628Ac7C489515402235FeAD71D1913','0x943A29E7ae51A4798823ca9eEd2ed533B2A22C72',
  '0xF6f373a037c30F0e5010d854385cA89185AE638b','0x7C38C00C30BEe9378381E7B6135d7283356D71b1',
  '0x451B1295aA84FD6d6b58af1a5002eA1b1A1913A0',
];
let priceCache = { at: 0, px: null };
// One slow feed, or one rate-limited minute, should not empty the shelf: a
// stale price is better than none, and a missing one keeps its last value.
async function readFeed(addr) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const r = await fetch(UPSTREAM, { method: 'POST', headers: { 'content-type': 'application/json', 'user-agent': UA },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_call', params: [{ to: addr, data: '0xfeaf968c' }, 'latest'] }) });
      const j = await r.json();
      if (j.result) return Number(BigInt('0x' + j.result.slice(2 + 64, 2 + 128))) / 1e8;
    } catch {}
    await new Promise(r => setTimeout(r, 250));
  }
  return null;
}

let refreshing = null;
async function prices() {
  if (priceCache.px && Date.now() - priceCache.at < 30_000) return priceCache.px;
  if (refreshing) return refreshing;
  refreshing = (async () => {
    const out = [1];
    let got = 0;
    for (let i = 0; i < FEEDS.length; i++) {
      const p = await readFeed(FEEDS[i]);
      if (p !== null) { out.push(p); got++; }
      else out.push(priceCache.px ? priceCache.px[i + 1] : null);
    }
    if (got > 0) priceCache = { at: Date.now(), px: out };
    return priceCache.px || out;
  })().finally(() => { refreshing = null; });
  return refreshing;
}

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.webp': 'image/webp', '.png': 'image/png', '.ico': 'image/x-icon', '.css': 'text/css' };
const SECURITY = {
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
  'strict-transport-security': 'max-age=31536000',
};

function sendText(req, res, status, headers, body) {
  const buf = Buffer.isBuffer(body) ? body : Buffer.from(body);
  const wantsGzip = /\bgzip\b/.test(req.headers['accept-encoding'] || '') && buf.length > 512;
  const h = { ...SECURITY, ...headers };
  if (wantsGzip && /^(text\/|application\/json)/.test(h['content-type'] || '')) {
    h['content-encoding'] = 'gzip';
    res.writeHead(status, h).end(gzipSync(buf));
  } else {
    res.writeHead(status, h).end(buf);
  }
}

http.createServer(async (req, res) => {
  // -- RPC proxy ----------------------------------------------------------
  if (req.url === '/api/rpc') {
    const origin = req.headers.origin;
    if (origin && !SITE_ORIGINS.has(origin)) {
      return sendText(req, res, 403, { 'content-type': 'application/json', 'cache-control': 'no-store' }, '{"error":"this proxy serves aumzero.com only"}');
    }
    if (req.method !== 'POST') return sendText(req, res, 405, { 'content-type': 'application/json' }, '{"error":"POST only"}');
    let body = '';
    req.on('data', c => { body += c; if (body.length > 10000) req.destroy(); });
    req.on('end', async () => {
      try {
        const parsed = JSON.parse(body);
        if (!ALLOW.has(parsed.method)) return sendText(req, res, 400, { 'content-type': 'application/json', 'cache-control': 'no-store' }, '{"error":"method not allowed"}');
        if (parsed.method === 'eth_getLogs' && !AUM0S.has(String(parsed.params?.[0]?.address).toLowerCase())) {
          return sendText(req, res, 400, { 'content-type': 'application/json', 'cache-control': 'no-store' }, '{"error":"logs served for the AUM0 contract only"}');
        }
        const r = await fetch(UPSTREAM, { method: 'POST', headers: { 'content-type': 'application/json', 'user-agent': UA }, body });
        sendText(req, res, r.status, { 'content-type': 'application/json', 'cache-control': 'no-store' }, await r.text());
      } catch (e) { sendText(req, res, 502, { 'content-type': 'application/json', 'cache-control': 'no-store' }, JSON.stringify({ error: String(e.message) })); }
    });
    return;
  }

  // -- cached feed prices -------------------------------------------------
  if (req.url === '/api/prices') {
    try {
      const px = await prices();
      if (!px || px.some(v => v === null)) throw new Error('feeds warming up');
      return sendText(req, res, 200, { 'content-type': 'application/json', 'cache-control': 'public, max-age=20' }, JSON.stringify(px));
    } catch (e) {
      return sendText(req, res, 503, { 'content-type': 'application/json', 'cache-control': 'no-store' }, JSON.stringify({ error: String(e.message) }));
    }
  }

  // -- static files -------------------------------------------------------
  const path = normalize(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
  try {
    const data = await readFile(join(ROOT, path === '' ? 'index.html' : path));
    const ct = MIME[extname(path)] || 'application/octet-stream';
    // The page itself is always fresh; assets are content-stable and cache long.
    const cache = ct.startsWith('text/html') ? 'no-store' : 'public, max-age=86400';
    sendText(req, res, 200, { 'content-type': ct, 'cache-control': cache }, data);
  } catch {
    try {
      sendText(req, res, 200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' }, await readFile(join(ROOT, 'index.html')));
    } catch { sendText(req, res, 404, { 'content-type': 'text/html' }, 'not found'); }
  }
}).listen(PORT, () => {
  console.log('aumzero.com serving on', PORT);
  prices().then(p => console.log('[prices] warm,', p.filter(Boolean).length, 'feeds')).catch(() => {});
});

import('./keeper.mjs').then(m => m.startKeeper()).catch(e => console.log('[keeper] not started:', e.message));
