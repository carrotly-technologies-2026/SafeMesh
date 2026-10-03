import { createHash, sign, timingSafeEqual, verify } from 'node:crypto';
import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { TextDecoder } from 'node:util';
import { DEFAULT_AUTHORITY_DIR, assertPinnedAuthority, atomicPrivateWrite, loadAuthority } from './prepare-demo-authority.mjs';

export const SERVICE = 'safemesh-demo-authority';
const MAX_BODY = 8192;
const MAX_RECEIPTS = 128;
const MAX_JOURNAL = 2 * 1024 * 1024;
const REQUIRED = ['requestId', 'title', 'body', 'area', 'language', 'severity', 'expiresInMinutes'];

// Exact SafeMesh.Alert.v2 domain and field order from AlertProtocol.ets. A test
// runs real envelopes through that source so this is not a second protocol.
export function canonical(payload) {
  const fields = [payload.version === 2 ? 'SafeMesh.Alert.v2' : 'SafeMesh.Alert.v1',
    payload.keyId, payload.alertId, String(payload.revision), String(payload.issuedAt), String(payload.expiresAt),
    payload.severity, payload.area, payload.title, payload.body, JSON.stringify(payload.shelterIds),
    payload.drill ? '1' : '0', String(payload.maxHops)];
  if (payload.version === 2) fields.push(payload.language === undefined ? '' : payload.language,
    JSON.stringify((payload.translations ?? []).map(item => [item.language, item.area, item.title, item.body])));
  return JSON.stringify(fields);
}

function validText(value, maximum, multiline = false) {
  return typeof value === 'string' && value.length >= 1 && value.length <= maximum && value.trim().length > 0 &&
    !(multiline ? /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/ : /[\u0000-\u001f\u007f]/).test(value) &&
    !/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/u.test(value);
}

export function validateDraft(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === REQUIRED.length && REQUIRED.every(key => Object.hasOwn(value, key)) &&
    typeof value.requestId === 'string' && /^[a-f0-9]{32}$/.test(value.requestId) &&
    validText(value.title, 160) && validText(value.body, 1200, true) && validText(value.area, 120) &&
    ['pl', 'en'].includes(value.language) && ['info', 'warning', 'critical'].includes(value.severity) &&
    Number.isInteger(value.expiresInMinutes) && value.expiresInMinutes >= 15 && value.expiresInMinutes <= 1440;
}

function draftHash(draft) {
  return createHash('sha256').update(JSON.stringify(REQUIRED.map(key => draft[key]))).digest('hex');
}

function payloadFor(draft, authority, now) {
  return { version: 2, keyId: authority.keyId, alertId: `authority-${draft.requestId}`, revision: 1,
    issuedAt: now, expiresAt: now + draft.expiresInMinutes * 60_000, severity: draft.severity,
    area: draft.area, title: draft.title, body: draft.body, shelterIds: [], drill: true, maxHops: 8,
    language: draft.language, translations: [] };
}

function loadReceipts(filename, authority) {
  if (!existsSync(filename)) return new Map();
  try {
    if (statSync(filename).size > MAX_JOURNAL) throw new Error();
    const data = JSON.parse(readFileSync(filename, 'utf8'));
    if (data.protocol !== 1 || data.keyId !== authority.keyId || data.publicKeyDer !== authority.publicKeyDer ||
        !Array.isArray(data.receipts) || data.receipts.length > MAX_RECEIPTS) throw new Error();
    const receipts = new Map();
    for (const receipt of data.receipts) {
      const { requestId, envelope } = receipt;
      const p = envelope?.payload;
      const draft = { requestId, title: p?.title, body: p?.body, area: p?.area, language: p?.language,
        severity: p?.severity, expiresInMinutes: (p?.expiresAt - p?.issuedAt) / 60_000 };
      if (!validateDraft(draft) || !Number.isSafeInteger(p.issuedAt) || p.issuedAt <= 0 ||
          JSON.stringify(p) !== JSON.stringify(payloadFor(draft, authority, p.issuedAt)) ||
          receipt.draftHash !== draftHash(draft) || receipts.has(requestId) || envelope.hops !== 0 ||
          typeof envelope.signature !== 'string' || envelope.signature.length > 120 ||
          Buffer.byteLength(canonical(p)) > 4096 ||
          !verify('sha256', Buffer.from(canonical(p)), authority.publicKey, Buffer.from(envelope.signature, 'base64'))) throw new Error();
      receipts.set(requestId, receipt);
    }
    return receipts;
  } catch {
    throw new Error('Authority receipt journal is invalid or belongs to another key; startup refused without discarding receipts.');
  }
}

function readBody(request) {
  return new Promise((resolveBody, reject) => {
    let length = 0;
    const chunks = [];
    let complete = false;
    const fail = code => {
      if (!complete) { complete = true; reject(new Error(code)); }
    };
    request.on('data', chunk => {
      length += chunk.length;
      if (length > MAX_BODY) { chunks.length = 0; fail('too_large'); }
      else if (!complete) chunks.push(chunk);
    });
    request.on('end', () => {
      if (complete) return;
      complete = true;
      try { resolveBody(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)))); }
      catch { reject(new Error('invalid_request')); }
    });
    request.on('aborted', () => fail('invalid_request'));
    request.on('error', () => fail('invalid_request'));
  });
}

export async function startDemoAuthority({ directory = DEFAULT_AUTHORITY_DIR, port = 8768,
  authority = loadAuthority(directory), clock = Date.now, log = event => console.log(JSON.stringify(event)),
  maxRequestsPerMinute = 120, maxIssuesPerMinute = 12, persist = atomicPrivateWrite } = {}) {
  const journalPath = resolve(directory, 'receipt-journal.json');
  let receipts = loadReceipts(journalPath, authority);
  const expectedTokenHash = createHash('sha256').update(authority.token).digest();
  let budgetStart = clock();
  let requests = 0;
  let issues = 0;
  const server = createServer({ maxHeaderSize: 8192, requestTimeout: 5000, headersTimeout: 5000 }, async (request, response) => {
    let finished = false;
    const finish = (status, value) => {
      if (finished || response.destroyed) return;
      finished = true;
      clearTimeout(deadline);
      response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff', 'Connection': 'close' });
      response.end(JSON.stringify(value));
      if (status >= 400) log({ event: 'rejected', status, error: value.error });
    };
    const deadline = setTimeout(() => {
      finish(408, { error: 'invalid_request' });
      request.destroy();
    }, 5000);
    deadline.unref();
    response.on('close', () => { finished = true; clearTimeout(deadline); });
    try {
      const address = server.address();
      const allowedHosts = [`127.0.0.1:${address.port}`, `localhost:${address.port}`];
      if (!allowedHosts.includes(request.headers.host) || request.headers.origin !== undefined) {
        finish(403, { error: 'invalid_request' }); return;
      }
      const now = clock();
      if (now - budgetStart >= 60_000 || now < budgetStart) { budgetStart = now; requests = 0; issues = 0; }
      requests++;
      if (requests > maxRequestsPerMinute) { finish(429, { error: 'rate_limited' }); return; }
      if (request.method === 'GET' && request.url === '/health') {
        finish(200, { service: SERVICE, protocol: 1, exerciseOnly: true }); return;
      }
      const authorization = request.headers.authorization ?? '';
      const candidate = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
      const hash = createHash('sha256').update(candidate).digest();
      const matched = timingSafeEqual(hash, expectedTokenHash);
      if (!matched || !/^Bearer [a-f0-9]{64}$/.test(authorization)) {
        finish(401, { error: 'unauthorized' }); return;
      }
      if (request.method === 'GET' && request.url === '/session') {
        finish(200, { service: SERVICE, protocol: 1, keyId: authority.keyId, publicKeyDer: authority.publicKeyDer,
          exerciseOnly: true, authorized: true, expiresInMinutes: { min: 15, max: 1440 } }); return;
      }
      if (request.method !== 'POST' || request.url !== '/alerts') { finish(404, { error: 'invalid_request' }); return; }
      if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers['content-type'] ?? '') ||
          (request.headers['content-encoding'] !== undefined && request.headers['content-encoding'] !== 'identity')) {
        finish(415, { error: 'invalid_request' }); return;
      }
      if (Number(request.headers['content-length']) > MAX_BODY) { finish(413, { error: 'too_large' }); return; }
      const draft = await readBody(request);
      if (finished || response.destroyed) return;
      if (!validateDraft(draft)) { finish(400, { error: 'invalid_request' }); return; }
      const existing = receipts.get(draft.requestId);
      const hashDraft = draftHash(draft);
      if (existing) {
        if (existing.draftHash !== hashDraft) { finish(409, { error: 'request_conflict' }); return; }
        if (existing.envelope.payload.expiresAt <= clock()) { finish(409, { error: 'request_expired' }); return; }
        finish(200, { envelope: existing.envelope });
        log({ event: 'replayed' }); return;
      }
      const issueTime = clock();
      const payload = payloadFor(draft, authority, issueTime);
      if (!Number.isSafeInteger(issueTime) || issueTime <= 0 || Buffer.byteLength(canonical(payload)) > 4096) {
        finish(400, { error: 'invalid_request' }); return;
      }
      if (issues >= maxIssuesPerMinute) { finish(429, { error: 'rate_limited' }); return; }
      const next = new Map([...receipts].filter(([, receipt]) => receipt.envelope.payload.expiresAt > issueTime));
      if (next.size >= MAX_RECEIPTS) { finish(429, { error: 'rate_limited' }); return; }
      const envelope = { payload, signature: sign('sha256', Buffer.from(canonical(payload)), authority.privateKey).toString('base64'), hops: 0 };
      next.set(draft.requestId, { requestId: draft.requestId, draftHash: hashDraft, envelope });
      try {
        persist(journalPath, `${JSON.stringify({ protocol: 1, keyId: authority.keyId, publicKeyDer: authority.publicKeyDer, receipts: [...next.values()] })}\n`);
      } catch { finish(500, { error: 'storage_failed' }); return; }
      receipts = next;
      issues++;
      finish(201, { envelope });
      log({ event: 'issued', activeReceipts: receipts.size });
    } catch (error) {
      finish(error.message === 'too_large' ? 413 : 400,
        { error: error.message === 'too_large' ? 'too_large' : 'invalid_request' });
    }
  });
  server.maxConnections = 8;
  server.maxRequestsPerSocket = 16;
  server.keepAliveTimeout = 2000;
  server.timeout = 5000;
  await new Promise((accept, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => { server.removeListener('error', reject); accept(); });
  });
  log({ event: 'listening', service: SERVICE, protocol: 1, host: '127.0.0.1', port: server.address().port, exerciseOnly: true });
  return { server, port: server.address().port, close: () => new Promise((accept, reject) => {
    server.close(error => error ? reject(error) : accept());
    server.closeIdleConnections();
  }) };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length !== 2) throw new Error('Usage: node scripts/demo-authority-server.mjs');
    const authority = loadAuthority();
    assertPinnedAuthority(authority);
    const service = await startDemoAuthority({ authority });
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { service.close().then(() => process.exit(0)); });
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
