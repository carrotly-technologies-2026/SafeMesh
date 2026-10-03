import assert from 'node:assert/strict';
import { createPublicKey, generateKeyPairSync, sign, verify } from 'node:crypto';
import { createRequire } from 'node:module';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
let ts;
try { ts = require('typescript'); } catch {
  const studio = process.env.DEVECO_CLI_STUDIO_PATH || join(process.env.USERPROFILE || '', 'DevEcoStudio');
  const compiler = process.env.ARKTS_TYPESCRIPT_PATH || join(studio,
    'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
  if (!existsSync(compiler)) throw new Error('Set ARKTS_TYPESCRIPT_PATH or DEVECO_CLI_STUDIO_PATH for host tests.');
  ts = require(compiler);
}

class MemoryStore {
  values = new Map();
  writes = 0;
  async read(key) { return this.values.get(key) || ''; }
  async write(key, value) { this.values.set(key, value); this.writes++; }
}

// Execute the actual ViewModel, protocol and generated fixtures. Only native
// crypto, UI observation and the timer/clock boundary are replaced. Every alert
// accepted in these tests has a real ECDSA signature; no verifier returns true.
function runtime({ testIssuer = true } = {}) {
  const timers = new Map();
  let nextTimer = 0;
  let now = 0;
  const pairs = testIssuer ? generateKeyPairSync('ec', { namedCurve: 'prime256v1' }) : undefined;
  const trust = pairs ? { DEMO_KEY_ID: 'safemesh-demo-authority-v1',
    DEMO_PUBLIC_KEY_DER: pairs.publicKey.export({ type: 'spki', format: 'der' }).toString('base64') } : undefined;
  const cryptoKit = { cryptoFramework: {
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
  const utilKit = { util: {
    TextEncoder: class { encodeInto(value) { return value === '' ? undefined : new TextEncoder().encode(value); } },
    Base64Helper: class { decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); } }
  } };
  class ClockDate extends Date { static now() { return now; } }
  const cache = new Map();
  function load(filename) {
    const path = resolve(filename);
    if (cache.has(path)) return cache.get(path).exports;
    const module = { exports: {} }; cache.set(path, module);
    const output = ts.transpileModule(readFileSync(path, 'utf8'), { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true
    }, fileName: path.replace(/\.ets$/, '.ts') }).outputText;
    const localRequire = specifier => {
      if (specifier === '@kit.CryptoArchitectureKit') return cryptoKit;
      if (specifier === '@kit.ArkTS') return utilKit;
      if (trust && specifier.endsWith('/DemoTrust')) return trust;
      if (specifier.endsWith('/LocalStore')) return { LocalStore: MemoryStore };
      if (specifier.startsWith('.')) return load(resolve(dirname(path), `${specifier}.ets`));
      throw new Error(`Unexpected display dependency ${specifier}`);
    };
    const execute = vm.runInThisContext(
      `(function(require,module,exports,Observed,Date,setTimeout,clearTimeout){${output}\n})`, { filename: path });
    execute(localRequire, module, module.exports, value => value, ClockDate,
      (callback, delay) => { const id = ++nextTimer; timers.set(id, { callback, at: now + delay }); return id; },
      id => timers.delete(id));
    return module.exports;
  }
  const model = resolve(root, 'entry/src/main/ets/model');
  const protocol = load(join(model, 'AlertProtocol.ets'));
  const fixtures = load(join(model, 'DemoAlerts.ets'));
  const { AlertViewModel } = load(resolve(root, 'entry/src/main/ets/viewmodel/AlertViewModel.ets'));
  now = fixtures.createDemoAlert().payload.issuedAt + 60_000;
  return { protocol, fixtures, timers,
    create(store = new MemoryStore()) { return new AlertViewModel(store); },
    now: () => now,
    signed(changes = {}) {
      if (!pairs) throw new Error('Synthetic signed alerts require a test-only ephemeral issuer.');
      const alert = fixtures.createDemoAlert(); Object.assign(alert.payload, changes);
      alert.signature = sign('sha256', Buffer.from(protocol.canonicalPayload(alert.payload)), pairs.privateKey).toString('base64');
      return alert;
    },
    advanceTo(time) {
      assert.ok(time >= now);
      for (let calls = 0; calls < 1000; calls++) {
        const due = [...timers].filter(([, value]) => value.at <= time).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) { now = time; return; }
        const [id, value] = due; now = value.at; timers.delete(id); value.callback();
      }
      throw new Error('Expiry timer failed to converge');
    }
  };
}

test('multiple verified arrivals form an unread inbox; selecting older detail never changes latest Home', async () => {
  const r = runtime(); const alerts = r.create(); const now = r.now();
  const latest = r.signed({ alertId: 'latest', issuedAt: now - 1000, title: 'Latest by issue time' });
  const older = r.signed({ alertId: 'older', issuedAt: now - 2000, title: 'Older issue, later arrival' });
  latest.hops = 1; older.hops = 2;
  await alerts.receive(latest, 'A'); const homeIdentity = alerts.currentIdentity;
  r.advanceTo(now + 100); await alerts.receive(older, 'B');
  assert.equal(alerts.inbox.length, 2); assert.equal(alerts.unreadCount, 2);
  assert.equal(alerts.inbox[0].alertId, 'older'); assert.equal(alerts.title, latest.payload.title);
  const olderIdentity = alerts.inbox[0].identity;
  assert.equal(alerts.arrivalIdentity, olderIdentity); assert.equal(alerts.arrivalSequence, 2);
  assert.equal(alerts.inbox[0].sourcePeer, 'B'); assert.equal(alerts.inbox[0].hops, 2);
  assert.equal(alerts.inbox[0].receivedAt, now + 100);
  assert.equal(await alerts.openMessage(olderIdentity), true);
  assert.equal(alerts.selectedMessage().title, older.payload.title);
  assert.equal(alerts.currentIdentity, homeIdentity); assert.equal(alerts.unreadCount, 1);
  assert.equal(alerts.arrivalIdentity, ''); assert.equal(alerts.arrivalSequence, 2);
  assert.equal(alerts.selectMessage('unknown'), false); assert.equal(await alerts.markRead('unknown'), false);
  alerts.dispose();
});

test('duplicate cannot overwrite receipts or read state; a higher revision replaces one row and becomes unread', async () => {
  const r = runtime(); const alerts = r.create(); const original = r.signed({ alertId: 'revision-test' });
  original.hops = 1; await alerts.receive(original, 'A');
  const firstIdentity = alerts.currentIdentity, receivedAt = alerts.inbox[0].receivedAt;
  await alerts.openMessage(firstIdentity); r.advanceTo(r.now() + 50);
  const duplicate = structuredClone(original); duplicate.hops = 3;
  assert.equal((await alerts.receive(duplicate, 'C')).status, 'duplicate');
  assert.equal(alerts.unreadCount, 0); assert.equal(alerts.arrivalIdentity, ''); assert.equal(alerts.arrivalSequence, 1);
  assert.equal(alerts.inbox[0].sourcePeer, 'A'); assert.equal(alerts.inbox[0].hops, 1);
  assert.equal(alerts.inbox[0].receivedAt, receivedAt);
  const revision = r.signed({ alertId: 'revision-test', revision: 2, title: 'Updated signed content' });
  assert.equal((await alerts.receive(revision, 'B')).status, 'accepted');
  assert.equal(alerts.inbox.length, 1); assert.equal(alerts.unreadCount, 1); assert.equal(alerts.arrivalSequence, 2);
  assert.notEqual(alerts.arrivalIdentity, firstIdentity); assert.equal(alerts.inbox[0].revision, 2);
  assert.equal(alerts.selectedIdentity, firstIdentity); assert.equal(alerts.selectedMessage(), undefined);
  assert.equal((await alerts.receive(original, 'A')).status, 'duplicate');
  assert.equal(alerts.inbox[0].revision, 2); assert.equal(alerts.arrivalSequence, 2);
  const forged = structuredClone(revision); forged.payload.body = 'Forged text';
  assert.equal((await alerts.receive(forged, 'attacker')).status, 'invalid');
  assert.equal(alerts.inbox.length, 1); assert.equal(alerts.inbox[0].sourcePeer, 'B');
  alerts.dispose();
});

test('atomic inbox restore re-verifies content and retains read/provenance without arrival banners', async () => {
  const r = runtime(); const store = new MemoryStore(); const original = r.create(store);
  await original.receive(r.signed({ alertId: 'read-message' }), 'A');
  const readIdentity = original.currentIdentity; await original.markRead(readIdentity);
  await original.receive(r.signed({ alertId: 'unread-message' }), 'B');
  const before = original.inbox.map(item => ({ id: item.identity, unread: item.unread, receivedAt: item.receivedAt, source: item.sourcePeer }));
  assert.ok(store.values.get('inbox_state_v1')); original.dispose();
  const restored = r.create(store); await restored.restore();
  assert.deepEqual(restored.inbox.map(item => ({ id: item.identity, unread: item.unread, receivedAt: item.receivedAt, source: item.sourcePeer })), before);
  assert.equal(restored.unreadCount, 1); assert.equal(restored.arrivalIdentity, ''); assert.equal(restored.arrivalSequence, 0);
  assert.equal(restored.persistenceState, 'reverified'); restored.dispose();
  const saved = JSON.parse(store.values.get('inbox_state_v1'));
  saved.alerts[0].payload.body = 'Stored forgery';
  saved.metadata.push({ identity: 'not-a-verified-message', read: false, receivedAt: r.now(), sourcePeer: 'fake', hops: 0 });
  store.values.set('inbox_state_v1', JSON.stringify(saved));
  const rechecked = r.create(store); await rechecked.restore();
  assert.equal(rechecked.inbox.length, 1); assert.equal(rechecked.inbox[0].alertId, 'unread-message');
  assert.equal(rechecked.inbox.some(item => item.body === 'Stored forgery'), false); rechecked.dispose();
});

test('legacy caches restore as known/read with unknown receipt time; metadata never invents alerts', async () => {
  const r = runtime(); const store = new MemoryStore(); const alert = r.signed({ alertId: 'legacy-cache' });
  store.values.set('relay_cache_v1', JSON.stringify([alert]));
  const alerts = r.create(store); await alerts.restore();
  assert.equal(alerts.inbox.length, 1); assert.equal(alerts.inbox[0].unread, false);
  assert.equal(alerts.inbox[0].receivedAt, 0); assert.equal(alerts.inbox[0].sourcePeer, '');
  assert.equal(alerts.arrivalIdentity, ''); assert.equal(alerts.arrivalSequence, 0); alerts.dispose();
  store.values.set('inbox_state_v1', JSON.stringify({ version: 1, alerts: [], metadata: [
    { identity: 'fake', read: false, receivedAt: r.now(), sourcePeer: 'authority', hops: 0 }
  ] }));
  const empty = r.create(store); await empty.restore();
  assert.equal(empty.inbox.length, 0); assert.equal(empty.unreadCount, 0); empty.dispose();
});

test('concurrent restore, opening a saved item and receiving a new item preserve both read-state updates', async () => {
  const r = runtime(); const store = new MemoryStore(); const first = r.create(store);
  await first.receive(r.signed({ alertId: 'existing-read' }), 'A');
  const readId = first.inbox[0].identity; await first.markRead(readId);
  await first.receive(r.signed({ alertId: 'existing-unread' }), 'B');
  const openId = first.inbox.find(item => item.alertId === 'existing-unread').identity;
  first.dispose();
  let release; const gate = new Promise(resolve => { release = resolve; });
  store.read = async key => { await gate; return store.values.get(key) || ''; };
  const next = r.create(store); const restoring = next.restore();
  const opening = next.openMessage(openId);
  const receiving = next.receive(r.signed({ alertId: 'new-arrival' }), 'C');
  release(); await Promise.all([restoring, opening, receiving]);
  assert.equal(next.getMessage(readId).unread, false); assert.equal(next.getMessage(openId).unread, false);
  assert.equal(next.unreadCount, 1); assert.equal(next.arrivalSequence, 1);
  next.dispose(); const final = r.create(store); await final.restore();
  assert.equal(final.unreadCount, 1); assert.equal(final.inbox.length, 3); assert.equal(final.arrivalSequence, 0);
  final.dispose();
});

test('queued writes do not let a slow accepted snapshot overwrite a later read or second arrival', async () => {
  const r = runtime(); const store = new MemoryStore(); const alerts = r.create(store);
  let release, notifyBlocked;
  const gate = new Promise(resolve => { release = resolve; });
  const blocked = new Promise(resolve => { notifyBlocked = resolve; });
  store.write = async (key, value) => { notifyBlocked(); await gate; store.values.set(key, value); };
  const first = alerts.receive(r.signed({ alertId: 'slow-first' }), 'A');
  await blocked; const firstId = alerts.inbox[0].identity;
  const read = alerts.markRead(firstId);
  const second = alerts.receive(r.signed({ alertId: 'fast-second' }), 'B');
  release(); await Promise.all([first, read, second]); alerts.dispose();
  const restored = r.create(store); await restored.restore();
  assert.equal(restored.inbox.length, 2); assert.equal(restored.getMessage(firstId).unread, false);
  assert.equal(restored.unreadCount, 1); restored.dispose();
});

test('failed atomic commit retains prior durable inbox while authenticated session content remains visible', async () => {
  const r = runtime(); const store = new MemoryStore(); const alerts = r.create(store);
  await alerts.receive(r.signed({ alertId: 'durable' }), 'A'); await alerts.markRead(alerts.currentIdentity);
  const prior = store.values.get('inbox_state_v1');
  store.write = async () => { throw new Error('Storage unavailable'); };
  assert.equal((await alerts.receive(r.signed({ alertId: 'memory-only' }), 'B')).status, 'accepted');
  assert.equal(alerts.inbox.length, 2); assert.equal(alerts.persistenceState, 'save_failed');
  assert.equal(store.values.get('inbox_state_v1'), prior); alerts.dispose();
  const restored = r.create(store); await restored.restore();
  assert.equal(restored.inbox.length, 1); assert.equal(restored.inbox[0].alertId, 'durable');
  assert.equal(restored.unreadCount, 0); restored.dispose();
});

test('a duplicate repairs a failed first commit without new unread, arrival, receipt time or source', async () => {
  const r = runtime(); const store = new MemoryStore(); const alerts = r.create(store);
  const write = store.write.bind(store);
  store.write = async () => { throw new Error('Temporary disk error'); };
  const packet = r.signed({ alertId: 'retry-publication' });
  assert.equal((await alerts.receive(packet, 'authority')).status, 'accepted');
  assert.equal(alerts.persistenceState, 'save_failed'); assert.equal(store.values.has('inbox_state_v1'), false);
  const identity = alerts.currentIdentity, receivedAt = alerts.inbox[0].receivedAt, sequence = alerts.arrivalSequence;
  alerts.dismissArrival(); r.advanceTo(r.now() + 1000); store.write = write;
  packet.hops = 2;
  assert.equal((await alerts.receive(packet, 'B')).status, 'duplicate');
  assert.equal(alerts.persistenceState, 'saved'); assert.equal(alerts.unreadCount, 1);
  assert.equal(alerts.arrivalSequence, sequence); assert.equal(alerts.arrivalIdentity, '');
  assert.equal(alerts.getMessage(identity).receivedAt, receivedAt);
  assert.equal(alerts.getMessage(identity).sourcePeer, 'authority'); assert.equal(alerts.getMessage(identity).hops, 0);
  alerts.dispose(); const restored = r.create(store); await restored.restore();
  assert.equal(restored.inbox.length, 1); assert.equal(restored.unreadCount, 1);
  assert.equal(restored.getMessage(identity).receivedAt, receivedAt); restored.dispose();
});

test('opening an already-read item retries a failed read-state commit and survives restart without a new banner', async () => {
  const r = runtime(); const store = new MemoryStore(); const alerts = r.create(store);
  await alerts.receive(r.signed({ alertId: 'retry-read' }), 'A'); const identity = alerts.currentIdentity;
  const write = store.write.bind(store); store.write = async () => { throw new Error('Temporary disk error'); };
  assert.equal(await alerts.openMessage(identity), true);
  assert.equal(alerts.persistenceState, 'save_failed'); assert.equal(alerts.unreadCount, 0);
  assert.equal(JSON.parse(store.values.get('inbox_state_v1')).metadata[0].read, false);
  store.write = write; assert.equal(await alerts.openMessage(identity), true);
  assert.equal(alerts.persistenceState, 'saved'); assert.equal(alerts.arrivalSequence, 1);
  assert.equal(alerts.arrivalIdentity, ''); alerts.dispose();
  const restored = r.create(store); await restored.restore();
  assert.equal(restored.unreadCount, 0); assert.equal(restored.arrivalSequence, 0); restored.dispose();
});

test('all inbox rows localize signed content with detached snapshots and no new arrival event', async () => {
  const r = runtime(); const alerts = r.create();
  await alerts.receive(r.signed({ alertId: 'bilingual' }), 'A');
  await alerts.receive(r.signed({ alertId: 'source-only', translations: [] }), 'B');
  const prior = alerts.inbox, sequence = alerts.arrivalSequence;
  const bilingualId = alerts.inbox.find(item => item.alertId === 'bilingual').identity;
  alerts.selectMessage(bilingualId); alerts.setLanguage('en');
  assert.notEqual(alerts.inbox, prior); assert.notEqual(alerts.inbox[0], prior[0]);
  assert.equal(alerts.selectedMessage().contentLanguage, 'en');
  assert.equal(alerts.inbox.find(item => item.alertId === 'source-only').languageFallback, true);
  assert.equal(alerts.arrivalSequence, sequence);
  alerts.inbox.find(item => item.identity === bilingualId).title = 'Caller mutation';
  alerts.inbox.length = 0;
  assert.notEqual(alerts.getMessage(bilingualId).title, 'Caller mutation');
  assert.equal(alerts.allAccepted().length, 2); alerts.setLanguage('pl');
  assert.equal(alerts.inbox.length, 2); assert.equal(alerts.selectedMessage().contentLanguage, 'pl');
  alerts.dispose();
});

test('the earliest inbox expiry prunes an unselected row, unread count and banner before the Home alert expires', async () => {
  const r = runtime(); const alerts = r.create(); const now = r.now();
  const current = r.signed({ alertId: 'current', issuedAt: now - 1000, expiresAt: now + 10_000 });
  const older = r.signed({ alertId: 'early-expiry', issuedAt: now - 2000, expiresAt: now + 1000 });
  await alerts.receive(current, 'A'); const home = alerts.currentIdentity;
  await alerts.receive(older, 'B'); const expiring = alerts.arrivalIdentity; alerts.selectMessage(expiring);
  assert.equal(alerts.unreadCount, 2); assert.equal(r.timers.size, 1);
  r.advanceTo(now + 1000);
  assert.equal(alerts.currentIdentity, home); assert.equal(alerts.inbox.length, 1); assert.equal(alerts.unreadCount, 1);
  assert.equal(alerts.arrivalIdentity, ''); assert.equal(alerts.selectedMessage(), undefined);
  assert.equal(alerts.arrivalSequence, 2); assert.equal(r.timers.size, 1);
  r.advanceTo(now + 10_000);
  assert.equal(alerts.inbox.length, 0); assert.equal(alerts.unreadCount, 0); assert.equal(alerts.received, false);
  assert.equal(r.timers.size, 0);
});

test('inbox shares the 128-message bound and constrains unsigned source metadata', async () => {
  const r = runtime(); const store = new MemoryStore(); const alerts = r.create(store);
  for (let index = 0; index < 128; index++) {
    assert.equal((await alerts.receive(r.signed({ alertId: `bounded-${index}` }), '\n' + 'B'.repeat(200))).status, 'accepted');
  }
  assert.equal(alerts.inbox.length, 128); assert.equal(alerts.unreadCount, 128); assert.equal(alerts.arrivalSequence, 128);
  assert.equal(alerts.inbox[0].sourcePeer.length, 96); assert.equal(alerts.inbox[0].sourcePeer.includes('\n'), false);
  assert.ok(store.values.get('inbox_state_v1').length <= 128 * 8192);
  assert.equal((await alerts.receive(r.signed({ alertId: 'overflow' }), 'C')).status, 'capacity');
  assert.equal(alerts.inbox.length, 128); assert.equal(alerts.arrivalSequence, 128); alerts.dispose();
});

