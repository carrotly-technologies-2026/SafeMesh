import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
let ts;
try { ts = require('typescript'); } catch {
  const studio = process.env.DEVECO_CLI_STUDIO_PATH || join(process.env.USERPROFILE || '', 'DevEcoStudio');
  const path = process.env.ARKTS_TYPESCRIPT_PATH || join(studio,
    'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
  if (!existsSync(path)) throw new Error('Set DEVECO_CLI_STUDIO_PATH for host tests.');
  ts = require(path);
}

function runtime() {
  let nonce = 0;
  const requests = [];
  const responses = [];
  const network = { http: {
    RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 0 },
    createHttp() { return {
      async request(url, options) {
        requests.push({ url, options });
        const next = responses.shift();
        if (typeof next === 'function') return next();
        if (!next) throw new Error('Unexpected request');
        return { responseCode: next.status, result: JSON.stringify(next.body) };
      }, destroy() {}
    }; }
  } };
  const cache = new Map();
  function load(filename) {
    const path = resolve(filename);
    if (cache.has(path)) return cache.get(path).exports;
    const module = { exports: {} }; cache.set(path, module);
    const output = ts.transpileModule(readFileSync(path, 'utf8'), { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true
    }, fileName: path.replace(/\.ets$/, '.ts') }).outputText;
    const localRequire = specifier => {
      if (specifier === '@kit.NetworkKit') return network;
      if (specifier === '@kit.CryptoArchitectureKit') return { cryptoFramework: {} };
      if (specifier === '@kit.ArkTS') return { util: {
        TextEncoder: class { encodeInto(s) { return new TextEncoder().encode(s); } }
      } };
      if (specifier.endsWith('/DeliveryProtocol')) return { createDeliveryId: () => (++nonce).toString(16).padStart(32, '0') };
      if (specifier.startsWith('.')) return load(resolve(dirname(path), specifier + '.ets'));
      throw new Error('Unexpected module: ' + specifier);
    };
    const run = vm.runInThisContext(`(function(require,module,exports,Observed){${output}\n})`, { filename: path });
    run(localRequire, module, module.exports, value => value);
    return module.exports;
  }
  const client = load(join(root, 'entry/src/main/ets/model/AuthorityClient.ets'));
  const model = load(join(root, 'entry/src/main/ets/viewmodel/AuthorityViewModel.ets'));
  const trust = load(join(root, 'entry/src/main/ets/model/DemoTrust.ets'));
  const fixture = load(join(root, 'entry/src/main/ets/model/DemoAlerts.ets')).createDemoAlert();
  const session = { service: 'safemesh-demo-authority', protocol: 1, keyId: trust.DEMO_KEY_ID,
    publicKeyDer: trust.DEMO_PUBLIC_KEY_DER, authorized: true, exerciseOnly: true };
  const draft = { requestId: '1'.repeat(32), title: 'Test title', body: 'Test body', area: 'Central Krakow',
    language: 'en', severity: 'warning', expiresInMinutes: 60 };
  const envelope = () => ({ ...structuredClone(fixture), payload: { ...structuredClone(fixture.payload),
    alertId: 'authority-' + draft.requestId, title: draft.title, body: draft.body, area: draft.area,
    language: draft.language, severity: draft.severity, translations: [],
    expiresAt: fixture.payload.issuedAt + 3600000 } });
  return { ...client, ...model, requests, responses, session, draft, envelope };
}

const credential = 'a'.repeat(64); // Deliberately fake credential, unrelated to the local demo service.

test('publishing needs an authorized session; malformed token never goes to the network', async () => {
  const r = runtime(), client = new r.AuthorityClient();
  await assert.rejects(client.publish(r.draft), /invalid_token/);
  await assert.rejects(client.login('not-a-token'), /invalid_token/);
  assert.equal(r.requests.length, 0);
});

test('authority session must match pinned key and exercise-only identity', async () => {
  const r = runtime(), client = new r.AuthorityClient();
  r.responses.push({ status: 200, body: { ...r.session, publicKeyDer: 'different' } });
  await assert.rejects(client.login(credential), /wrong_authority/);
  await assert.rejects(client.publish(r.draft), /invalid_token/);
  r.responses.push({ status: 200, body: { ...r.session, exerciseOnly: false } });
  await assert.rejects(client.login(credential), /invalid_response/);
});

test('native HTTP uses only loopback, disables redirects/proxy/cache and bounds responses', async () => {
  const r = runtime(), client = new r.AuthorityClient();
  r.responses.push({ status: 200, body: r.session }, { status: 201, body: { envelope: r.envelope() } });
  await client.login(credential);
  const result = await client.publish(r.draft);
  assert.equal(result.payload.alertId, 'authority-' + r.draft.requestId);
  assert.deepEqual(r.requests.map(r => r.url), ['http://127.0.0.1:8768/session', 'http://127.0.0.1:8768/alerts']);
  const { options } = r.requests[1];
  assert.equal(options.maxRedirects, 0); assert.equal(options.usingProxy, false);
  assert.equal(options.usingCache, false); assert.equal(options.maxLimit, 16384);
  assert.equal(options.header.Authorization, 'Bearer ' + credential);
  assert.deepEqual(JSON.parse(options.extraData), r.draft);
});

test('a mismatched returned draft is rejected before entering the recipient verifier', async () => {
  const r = runtime(), client = new r.AuthorityClient();
  const changed = r.envelope(); changed.payload.body = 'Different from what the issuer typed';
  r.responses.push({ status: 200, body: r.session }, { status: 201, body: { envelope: changed } });
  await client.login(credential);
  await assert.rejects(client.publish(r.draft), /invalid_response/);
});

test('unauthorized response erases session; logout rejects a late successful login', async () => {
  const r = runtime(), client = new r.AuthorityClient();
  r.responses.push({ status: 200, body: r.session }, { status: 401, body: { error: 'unauthorized' } });
  await client.login(credential);
  await assert.rejects(client.publish(r.draft), /invalid_token/);
  await assert.rejects(client.publish(r.draft), /invalid_token/);
  assert.equal(r.requests.length, 2);
  let finish;
  r.responses.push(() => new Promise(resolve => { finish = resolve; }));
  const pending = client.login(credential);
  client.logout();
  finish({ responseCode: 200, result: JSON.stringify(r.session) });
  await assert.rejects(pending, /cancelled/);
  await assert.rejects(client.publish(r.draft), /invalid_token/);
});

function publisher(r, verdict = 'accepted') {
  const calls = { drafts: [], received: [], relays: 0 };
  let nextFailure = '';
  let sequence = 0;
  const client = {
    async login(token) { assert.equal(token, credential); }, logout() {},
    createRequestId() { return (++sequence).toString(16).padStart(32, '0'); },
    async publish(draft) {
      calls.drafts.push(structuredClone(draft));
      if (nextFailure) { const failure = nextFailure; nextFailure = ''; throw new Error(failure); }
      const envelope = r.envelope();
      envelope.payload.alertId = 'authority-' + draft.requestId;
      envelope.payload.title = draft.title; envelope.payload.body = draft.body;
      return envelope;
    }
  };
  const alerts = { persistenceState: 'saved', async receive(envelope, source) {
    calls.received.push({ envelope, source }); return { status: verdict };
  } };
  const relay = { isConnected: true, peerCount: 1, async share() { calls.relays++; } };
  const value = new r.AuthorityViewModel(alerts, relay, client);
  value.tokenInput = credential; value.draftTitle = 'Published title'; value.draftBody = 'Published body';
  return { value, calls, relay, alerts, failNext(state = 'unavailable') { nextFailure = state; } };
}

test('publisher never forwards a rejected signature; signing privilege is separate from relay role', async () => {
  const r = runtime(), p = publisher(r, 'invalid');
  assert.equal(await p.value.publish(), false); assert.equal(p.calls.drafts.length, 0);
  p.value.tokenInput = credential; await p.value.login();
  assert.equal(p.value.tokenInput, '');
  assert.equal(await p.value.publish(), false);
  assert.equal(p.value.state, 'verification_failed'); assert.equal(p.calls.relays, 0);
});

test('successful publication enters the verifier then seeds forwarding automatically', async () => {
  const r = runtime(), p = publisher(r);
  await p.value.login();
  assert.equal(await p.value.publish(), true);
  assert.equal(p.calls.received.length, 1); assert.equal(p.calls.received[0].source, 'authority');
  assert.equal(p.calls.relays, 1); assert.equal(p.value.state, 'published');
  assert.equal(p.value.draftBody, ''); assert.ok(p.value.lastPublishedIdentity.length > 0);
  p.value.draftTitle = 'Offline draft'; p.value.draftBody = 'Keep until a neighbor appears';
  p.relay.isConnected = false; p.relay.peerCount = 0;
  assert.equal(await p.value.publish(), true); assert.equal(p.value.state, 'published_waiting');
});

test('uncertain response retry retains request ID; confirmed or edited drafts get a new ID', async () => {
  const r = runtime(), p = publisher(r);
  await p.value.login(); p.failNext();
  assert.equal(await p.value.publish(), false); assert.equal(p.value.state, 'unavailable');
  assert.equal(await p.value.publish(), true);
  assert.equal(p.calls.drafts[0].requestId, p.calls.drafts[1].requestId);
  p.value.draftTitle = 'Second alert'; p.value.draftBody = 'Second body';
  p.failNext(); assert.equal(await p.value.publish(), false);
  assert.notEqual(p.calls.drafts[1].requestId, p.calls.drafts[2].requestId);
  p.value.draftBody = 'Edited body'; assert.equal(await p.value.publish(), true);
  assert.notEqual(p.calls.drafts[2].requestId, p.calls.drafts[3].requestId);
});

test('failed mobile persistence retains the draft and retry ID and never claims saved or queues a volatile publication', async () => {
  const r = runtime(), p = publisher(r);
  await p.value.login(); p.relay.isConnected = false; p.relay.peerCount = 0;
  p.alerts.persistenceState = 'save_failed';
  assert.equal(await p.value.publish(), false);
  assert.equal(p.value.state, 'storage_failed'); assert.equal(p.calls.relays, 0);
  assert.equal(p.value.draftTitle, 'Published title'); assert.equal(p.value.draftBody, 'Published body');
  assert.equal(p.value.lastPublishedIdentity, '');
  const requestId = p.calls.drafts[0].requestId;
  p.alerts.receive = async (envelope, source) => {
    p.calls.received.push({ envelope, source });
    p.alerts.persistenceState = 'saved';
    return { status: 'duplicate' };
  };
  assert.equal(await p.value.publish(), true);
  assert.equal(p.calls.drafts[1].requestId, requestId);
  assert.equal(p.calls.relays, 1); assert.equal(p.value.state, 'published_waiting');
  assert.equal(p.value.draftTitle, ''); assert.equal(p.value.draftBody, '');
});

test('expired idempotency receipts are distinguished from a conflicting draft by the HTTP client', async () => {
  const r = runtime(), client = new r.AuthorityClient();
  r.responses.push({ status: 200, body: r.session },
    { status: 409, body: { error: 'request_expired' } },
    { status: 409, body: { error: 'request_conflict' } });
  await client.login(credential);
  await assert.rejects(client.publish(r.draft), /request_expired/);
  await assert.rejects(client.publish(r.draft), /request_conflict/);
});

test('expired uncertain publication keeps its text and only a later explicit attempt creates a fresh request ID', async () => {
  const r = runtime(), p = publisher(r); await p.value.login();
  p.failNext('request_expired');
  assert.equal(await p.value.publish(), false); assert.equal(p.value.state, 'request_expired');
  assert.equal(p.value.draftTitle, 'Published title'); assert.equal(p.value.draftBody, 'Published body');
  assert.equal(p.calls.drafts.length, 1); assert.equal(p.calls.relays, 0); assert.equal(p.value.authenticated, true);
  const expiredId = p.calls.drafts[0].requestId;
  assert.equal(await p.value.publish(), true);
  assert.notEqual(p.calls.drafts[1].requestId, expiredId);
  assert.equal(p.calls.drafts[1].title, p.calls.drafts[0].title);
  assert.equal(p.calls.drafts[1].body, p.calls.drafts[0].body);
  assert.equal(p.calls.relays, 1);
});
