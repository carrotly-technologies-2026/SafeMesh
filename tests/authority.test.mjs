import assert from 'node:assert/strict';
import { createPublicKey, verify } from 'node:crypto';
import { request as httpRequest } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import { assertPinnedAuthority, atomicPrivateWrite, loadAuthority, prepareAuthority } from '../scripts/prepare-demo-authority.mjs';
import { canonical, startDemoAuthority } from '../scripts/demo-authority-server.mjs';
import { generateDemoAlerts } from '../scripts/generate-demo-alerts.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
let ts;
try { ts = require('typescript'); } catch {
  const studio = process.env.DEVECO_CLI_STUDIO_PATH || join(process.env.USERPROFILE || '', 'DevEcoStudio');
  ts = require(process.env.ARKTS_TYPESCRIPT_PATH || join(studio,
    'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
}

// This is the actual recipient protocol, with only native crypto/UTF-8 adapted
// to Node and its public pin replaced by the test's isolated temporary key.
function recipientProtocol(authority) {
  const source = resolve(root, 'entry/src/main/ets/model/AlertProtocol.ets');
  const output = ts.transpileModule(readFileSync(source, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  }, fileName: source.replace(/\.ets$/, '.ts') }).outputText;
  const module = { exports: {} };
  const nativeCrypto = { cryptoFramework: {
    createAsyKeyGenerator(algorithm) {
      assert.equal(algorithm, 'ECC256');
      return { async convertKey(blob, secret) {
        assert.equal(secret, null);
        return { pubKey: createPublicKey({ key: Buffer.from(blob.data), format: 'der', type: 'spki' }) };
      } };
    },
    createVerify(algorithm) {
      assert.equal(algorithm, 'ECC256|SHA256');
      let key;
      return { async init(value) { key = value; },
        async verify(input, signature) { return verify('sha256', input.data, key, signature.data); } };
    }
  } };
  const localRequire = specifier => {
    if (specifier === './DemoTrust') return { DEMO_KEY_ID: authority.keyId, DEMO_PUBLIC_KEY_DER: authority.publicKeyDer };
    if (specifier === '@kit.CryptoArchitectureKit') return nativeCrypto;
    if (specifier === '@kit.ArkTS') return { util: {
      TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
      Base64Helper: class { decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); } }
    } };
    throw new Error(`Unexpected protocol dependency ${specifier}`);
  };
  vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename: source })(localRequire, module, module.exports);
  return module.exports;
}

function temporary(t) {
  const directory = mkdtempSync(join(tmpdir(), 'SafeMesh-authority-test-'));
  t.after(() => {
    assert.equal(dirname(resolve(directory)), resolve(tmpdir()));
    assert.ok(basename(directory).startsWith('SafeMesh-authority-test-'));
    rmSync(directory, { recursive: true, force: true });
  });
  return directory;
}

function draft(id = 1, changes = {}) {
  return { requestId: id.toString(16).padStart(32, '0'), title: 'Ćwiczenie: przerwa w łączności',
    body: 'To ćwiczenie. Sprawdź wskazany punkt na mapie.\nZachowaj spokój.', area: 'Kraków centrum',
    language: 'pl', severity: 'warning', expiresInMinutes: 30, ...changes };
}

async function serviceFor(t, options = {}) {
  const directory = temporary(t);
  const authority = prepareAuthority({ directory });
  const events = [];
  const service = await startDemoAuthority({ directory, authority, port: 0, log: event => events.push(event), ...options });
  t.after(() => service.close());
  return { ...service, directory, authority, events };
}

function request(service, { method = 'POST', path = '/alerts', body = draft(), raw,
  authenticated = true, headers = {}, chunked = false } = {}) {
  const bytes = raw ?? (method === 'POST' ? JSON.stringify(body) : undefined);
  return new Promise((accept, reject) => {
    const requestHeaders = { ...(authenticated ? { Authorization: `Bearer ${service.authority.token}` } : {}),
      ...(bytes !== undefined ? { 'Content-Type': 'application/json',
        ...(chunked ? {} : { 'Content-Length': Buffer.byteLength(bytes) }) } : {}), ...headers };
    const req = httpRequest({ host: '127.0.0.1', port: service.port, path, method, headers: requestHeaders }, response => {
      const chunks = [];
      response.on('data', data => chunks.push(data));
      response.on('end', () => {
        try { accept({ status: response.statusCode, headers: response.headers, body: JSON.parse(Buffer.concat(chunks)) }); }
        catch (error) { reject(error); }
      });
    });
    req.on('error', reject);
    if (bytes !== undefined) req.write(bytes);
    req.end();
  });
}

test('preparation reuses local key/token; only explicit rotation replaces them; corrupt secrets fail closed', t => {
  const directory = temporary(t);
  const first = prepareAuthority({ directory });
  const second = prepareAuthority({ directory });
  assert.equal(first.publicKeyDer, second.publicKeyDer);
  assert.equal(first.token, second.token);
  assert.match(first.token, /^[a-f0-9]{64}$/);
  assert.equal(readFileSync(join(directory, 'session-token.txt'), 'utf8').trim(), first.token);
  const rotated = prepareAuthority({ directory, rotate: true });
  assert.notEqual(rotated.publicKeyDer, first.publicKeyDer);
  assert.notEqual(rotated.token, first.token);
  writeFileSync(join(directory, 'authority.json'), '{broken');
  assert.throws(() => prepareAuthority({ directory }), /invalid/);
  assert.equal(readFileSync(join(directory, 'authority.json'), 'utf8'), '{broken');
});

test('fixture refresh preserves the authority pin and requires explicit adoption of a new public key', t => {
  const directory = temporary(t);
  const authority = prepareAuthority({ directory });
  const application = join(directory, 'app');
  assert.throws(() => generateDemoAlerts({ root: application, authority }), /--update-public-key/);
  generateDemoAlerts({ root: application, authority, updatePublicKey: true });
  assertPinnedAuthority(authority, application);
  const trustPath = join(application, 'entry/src/main/ets/model/DemoTrust.ets');
  const before = readFileSync(trustPath, 'utf8');
  generateDemoAlerts({ root: application, authority });
  assert.equal(readFileSync(trustPath, 'utf8'), before);
  const artifacts = before + readFileSync(join(application, 'entry/src/main/ets/model/DemoAlerts.ets'), 'utf8');
  assert.ok(!artifacts.includes(authority.token));
  assert.ok(!artifacts.includes('PRIVATE KEY'));
  const other = prepareAuthority({ directory, rotate: true });
  assert.throws(() => generateDemoAlerts({ root: application, authority: other }), /differs/);
  assert.equal(readFileSync(trustPath, 'utf8'), before);
});

test('health reveals no key/token; session and issuance require the separate bearer credential', async t => {
  const service = await serviceFor(t);
  const health = await request(service, { method: 'GET', path: '/health', authenticated: false });
  assert.deepEqual(health.body, { service: 'safemesh-demo-authority', protocol: 1, exerciseOnly: true });
  assert.equal(health.headers['access-control-allow-origin'], undefined);
  for (const path of ['/session', '/alerts']) {
    for (const authorization of ['', 'Bearer bad', `Bearer ${'0'.repeat(64)}`, `bearer ${service.authority.token}`]) {
      const response = await request(service, { method: path === '/session' ? 'GET' : 'POST', path,
        authenticated: false, headers: { Authorization: authorization } });
      assert.equal(response.status, 401);
      assert.equal(response.body.error, 'unauthorized');
    }
  }
  assert.ok(!existsSync(join(service.directory, 'receipt-journal.json')));
  const session = await request(service, { method: 'GET', path: '/session' });
  assert.deepEqual(session.body, { service: 'safemesh-demo-authority', protocol: 1,
    keyId: service.authority.keyId, publicKeyDer: service.authority.publicKeyDer, authorized: true,
    exerciseOnly: true, expiresInMinutes: { min: 15, max: 1440 } });
  assert.ok(!JSON.stringify(session.body).includes(service.authority.token));
});

test('actual recipient protocol accepts issued v2 signatures and rejects tampering and unpinned authorities', async t => {
  const service = await serviceFor(t);
  const recipient = recipientProtocol(service.authority);
  for (const language of ['pl', 'en']) {
    const result = await request(service, { body: draft(language === 'pl' ? 1 : 2, { language }) });
    assert.equal(result.status, 201);
    const envelope = result.body.envelope;
    assert.equal(envelope.payload.drill, true);
    assert.equal(envelope.payload.version, 2);
    assert.equal(envelope.payload.maxHops, 8);
    assert.equal(envelope.payload.revision, 1);
    assert.equal(envelope.payload.language, language);
    assert.deepEqual(envelope.payload.translations, []);
    assert.equal(envelope.payload.expiresAt - envelope.payload.issuedAt, 30 * 60_000);
    assert.equal(canonical(envelope.payload), recipient.canonicalPayload(envelope.payload));
    assert.equal((await new recipient.RelayEngine().ingest(envelope)).status, 'accepted');
    const modified = structuredClone(envelope); modified.payload.body += ' changed';
    assert.equal((await new recipient.RelayEngine().ingest(modified)).status, 'invalid');
    const otherAuthority = prepareAuthority({ directory: join(service.directory, `other-${language}`) });
    const unpinned = recipientProtocol(otherAuthority);
    assert.equal((await new unpinned.RelayEngine().ingest(envelope)).status, 'invalid');
  }
});

test('distinct client request IDs produce distinct signed alert identities; metadata logs omit alert content and secrets', async t => {
  const service = await serviceFor(t);
  const first = (await request(service, { body: draft(1) })).body.envelope;
  const second = (await request(service, { body: draft(2) })).body.envelope;
  assert.notEqual(first.payload.alertId, second.payload.alertId);
  assert.equal(first.payload.alertId, `authority-${draft(1).requestId}`);
  const logs = JSON.stringify(service.events);
  for (const secret of [service.authority.token, service.authority.privateKeyPem, service.authority.publicKeyDer,
    draft().title, draft().body, draft().area]) assert.ok(!logs.includes(secret));
});

test('same request retries return byte-equivalent receipt after a restart; changed drafts cannot reuse its ID', async t => {
  const directory = temporary(t);
  const authority = prepareAuthority({ directory });
  let now = Date.now();
  let service = await startDemoAuthority({ directory, authority, port: 0, clock: () => now, log: () => {} });
  t.after(() => service.close());
  let client = { ...service, authority };
  const first = await request(client);
  assert.equal(first.status, 201);
  now += 60_000;
  const replay = await request(client);
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, first.body);
  const conflict = await request(client, { body: draft(1, { title: 'Different title' }) });
  assert.deepEqual([conflict.status, conflict.body.error], [409, 'request_conflict']);
  await service.close();
  service = await startDemoAuthority({ directory, authority: loadAuthority(directory), port: 0, clock: () => now, log: () => {} });
  client = { ...service, authority };
  const restored = await request(client);
  assert.equal(restored.status, 200);
  assert.deepEqual(restored.body, first.body);
  assert.throws(() => prepareAuthority({ directory, rotate: true }), /archived receipt-journal/);
});

test('concurrent duplicate requests persist and return exactly one issued envelope', async t => {
  const service = await serviceFor(t);
  const responses = await Promise.all(Array.from({ length: 6 }, () => request(service)));
  assert.equal(responses.filter(item => item.status === 201).length, 1);
  assert.equal(responses.filter(item => item.status === 200).length, 5);
  for (const response of responses) assert.deepEqual(response.body, responses[0].body);
  const journal = JSON.parse(readFileSync(join(service.directory, 'receipt-journal.json'), 'utf8'));
  assert.equal(journal.receipts.length, 1);
});

test('strict draft schema rejects signer-controlled fields, bad IDs, limits, controls and invalid text', async t => {
  const service = await serviceFor(t);
  const cases = [null, [], { ...draft(), keyId: 'attacker' }, { ...draft(), drill: false },
    { ...draft(), signature: 'x' }, { ...draft(), maxHops: 100 }, { ...draft(), role: 'A' },
    draft(1, { requestId: 'A'.repeat(32) }), draft(1, { requestId: '' }),
    draft(1, { title: '' }), draft(1, { title: ' ' }), draft(1, { title: 'x'.repeat(161) }),
    draft(1, { body: 'x'.repeat(1201) }), draft(1, { area: 'x'.repeat(121) }),
    draft(1, { title: 'bad\nline' }), draft(1, { body: 'bad\u0000' }), draft(1, { title: '\ud800' }),
    draft(1, { expiresInMinutes: 14 }), draft(1, { expiresInMinutes: 1441 }),
    draft(1, { expiresInMinutes: 20.5 }), draft(1, { expiresInMinutes: '30' }),
    draft(1, { language: 'de' }), draft(1, { severity: 'emergency' }),
    draft(1, { title: '界'.repeat(160), area: '界'.repeat(120), body: '界'.repeat(1200) })];
  for (const body of cases) {
    const response = await request(service, { body });
    assert.deepEqual([response.status, response.body.error], [400, 'invalid_request']);
  }
  assert.ok(!existsSync(join(service.directory, 'receipt-journal.json')));
});

test('HTTP boundary rejects browser Origin, foreign Host, wrong media type, malformed UTF-8 and oversized bodies', async t => {
  const service = await serviceFor(t);
  assert.equal(service.server.address().address, '127.0.0.1');
  for (const headers of [{ Origin: 'http://127.0.0.1' }, { Origin: 'null' }, { Host: `evil.test:${service.port}` },
    { Host: '127.0.0.1:8765' }]) assert.equal((await request(service, { headers })).status, 403);
  for (const headers of [{ 'Content-Type': 'text/plain' }, { 'Content-Encoding': 'gzip' }]) {
    assert.equal((await request(service, { headers })).status, 415);
  }
  assert.equal((await request(service, { raw: '{broken' })).status, 400);
  assert.equal((await request(service, { raw: Buffer.from([0xff]) })).status, 400);
  for (const chunked of [false, true]) {
    const result = await request(service, { raw: 'x'.repeat(8193), chunked });
    assert.deepEqual([result.status, result.body.error], [413, 'too_large']);
  }
});

test('failed durable write does not publish or acknowledge an alert; retry can succeed', async t => {
  let fail = true;
  const service = await serviceFor(t, { persist: (filename, content) => {
    if (fail) throw new Error('private storage failure detail should not be exposed');
    atomicPrivateWrite(filename, content);
  } });
  const failed = await request(service);
  assert.deepEqual([failed.status, failed.body], [500, { error: 'storage_failed' }]);
  assert.ok(!existsSync(join(service.directory, 'receipt-journal.json')));
  fail = false;
  assert.equal((await request(service)).status, 201);
  assert.equal((await request(service)).status, 200);
  assert.ok(!JSON.stringify(service.events).includes('private storage failure'));
});

test('new-signature rate budget does not prevent an idempotent retry and resets after its window', async t => {
  let now = Date.now();
  const service = await serviceFor(t, { clock: () => now, maxIssuesPerMinute: 1 });
  assert.equal((await request(service)).status, 201);
  assert.equal((await request(service)).status, 200);
  const limited = await request(service, { body: draft(2) });
  assert.deepEqual([limited.status, limited.body.error], [429, 'rate_limited']);
  now += 60_000;
  assert.equal((await request(service, { body: draft(2) })).status, 201);
});

test('request budget also bounds unauthenticated traffic', async t => {
  const service = await serviceFor(t, { maxRequestsPerMinute: 2 });
  assert.equal((await request(service, { authenticated: false })).status, 401);
  assert.equal((await request(service, { authenticated: false })).status, 401);
  assert.equal((await request(service, { authenticated: false })).status, 429);
});

test('journal is bounded to 128 active receipts and expired entries allow subsequent new requests', async t => {
  let now = Date.now();
  const service = await serviceFor(t, { clock: () => now, maxIssuesPerMinute: 1000, maxRequestsPerMinute: 1000 });
  for (let id = 1; id <= 128; id++) assert.equal((await request(service, { body: draft(id, { expiresInMinutes: 15 }) })).status, 201);
  assert.equal((await request(service, { body: draft(129) })).status, 429);
  now += 15 * 60_000;
  const expired = await request(service, { body: draft(1, { expiresInMinutes: 15 }) });
  assert.deepEqual([expired.status, expired.body.error], [409, 'request_expired']);
  assert.equal((await request(service, { body: draft(129) })).status, 201);
  const journal = JSON.parse(readFileSync(join(service.directory, 'receipt-journal.json'), 'utf8'));
  assert.equal(journal.receipts.length, 1);
});

test('tampered durable receipt causes startup refusal instead of resetting idempotency history', async t => {
  const directory = temporary(t);
  const authority = prepareAuthority({ directory });
  const service = await startDemoAuthority({ directory, authority, port: 0, log: () => {} });
  await request({ ...service, authority });
  await service.close();
  const path = join(directory, 'receipt-journal.json');
  const journal = JSON.parse(readFileSync(path, 'utf8'));
  journal.receipts[0].envelope.payload.body = 'forged';
  writeFileSync(path, JSON.stringify(journal));
  await assert.rejects(startDemoAuthority({ directory, authority, port: 0, log: () => {} }), /journal is invalid/);
  assert.ok(readFileSync(path, 'utf8').includes('forged'));
});
