import assert from 'node:assert/strict';
import { createPublicKey, generateKeyPairSync, sign, verify } from 'node:crypto';
import { createRequire } from 'node:module';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import { deriveMeshLabFixtures } from '../scripts/mesh-lab-fixtures.mjs';

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
function runtime({ testIssuer = false } = {}) {
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

test('PL/EN selection displays only signed variants and preserves identity, packet bytes and storage', async () => {
  const r = runtime(); const store = new MemoryStore(); const alerts = r.create(store);
  const original = r.fixtures.createDemoAlert();
  assert.equal((await alerts.receive(original)).status, 'accepted');
  assert.equal(alerts.title, original.payload.title);
  assert.equal(alerts.contentLanguage, 'pl');
  assert.equal(alerts.languageFallback, false);
  const identity = alerts.currentIdentity, packet = alerts.nextPacket(), writes = store.writes;
  alerts.setLanguage('en');
  assert.equal(alerts.title, original.payload.translations[0].title);
  assert.equal(alerts.body, original.payload.translations[0].body);
  assert.equal(alerts.area, original.payload.translations[0].area);
  assert.equal(alerts.contentLanguage, 'en');
  assert.equal(alerts.verificationState, 'verified');
  assert.equal(alerts.issuedAt, original.payload.issuedAt);
  assert.equal(alerts.expiresAt, original.payload.expiresAt);
  alerts.setLanguage('unsupported');
  assert.equal(alerts.contentLanguage, 'en');
  alerts.setLanguage('pl');
  assert.equal(alerts.title, original.payload.title);
  assert.equal(alerts.currentIdentity, identity);
  assert.equal(alerts.nextPacket(), packet);
  assert.equal(store.writes, writes);
  assert.equal(r.timers.size, 1);
  alerts.dispose();
});

test('a forged alternate is rejected without changing the authentic localized alert', async () => {
  const r = runtime(); const alerts = r.create();
  await alerts.receive(r.fixtures.createDemoAlert()); alerts.setLanguage('en');
  const title = alerts.title, body = alerts.body, identity = alerts.currentIdentity;
  const forged = r.fixtures.createDemoAlert(); forged.payload.translations[0].body = 'Injected instruction';
  assert.equal((await alerts.receive(forged)).status, 'invalid');
  assert.equal(alerts.lastReceiveState, 'invalid');
  assert.equal(alerts.verificationState, 'verified');
  assert.equal(alerts.title, title); assert.equal(alerts.body, body);
  assert.equal(alerts.currentIdentity, identity);
  alerts.dispose();
});

test('missing signed alternate falls back explicitly to the original and never synthesizes content', async () => {
  const r = runtime({ testIssuer: true }); const alerts = r.create();
  const original = r.signed({ translations: undefined });
  alerts.setLanguage('en'); await alerts.receive(original);
  assert.equal(alerts.title, original.payload.title);
  assert.equal(alerts.body, original.payload.body);
  assert.equal(alerts.contentLanguage, 'pl'); assert.equal(alerts.languageFallback, true);
  alerts.setLanguage('pl'); assert.equal(alerts.languageFallback, false);
  alerts.dispose();
});

test('legacy v1 content remains original with an unknown-language fallback in both interface languages', async () => {
  const r = runtime({ testIssuer: true }); const alerts = r.create();
  const legacy = r.signed({ version: 1, language: undefined, translations: undefined, title: 'Legacy original' });
  assert.equal((await alerts.receive(legacy)).status, 'accepted');
  for (const language of ['en', 'pl']) {
    alerts.setLanguage(language);
    assert.equal(alerts.title, 'Legacy original'); assert.equal(alerts.contentLanguage, 'und');
    assert.equal(alerts.languageFallback, true);
  }
  alerts.dispose();
});

test('restoration verifies before selecting requested content; corrupt persisted alternate stays hidden', async () => {
  const r = runtime(); const store = new MemoryStore(); const first = r.create(store);
  await first.receive(r.fixtures.createDemoAlert()); first.dispose();
  const restored = r.create(store); restored.setLanguage('en');
  assert.equal(restored.title, ''); await restored.restore();
  assert.equal(restored.title, r.fixtures.createDemoAlert().payload.translations[0].title);
  assert.equal(restored.persistenceState, 'reverified'); restored.dispose();
  const forged = r.fixtures.createDemoAlert(); forged.payload.translations[0].body = 'Stored forgery';
  const corrupted = new MemoryStore(); corrupted.values.set('relay_cache_v1', JSON.stringify([forged]));
  const rejected = r.create(corrupted); rejected.setLanguage('en'); await rejected.restore();
  assert.equal(rejected.received, false); assert.equal(rejected.title, '');
  assert.equal(rejected.currentIdentity, ''); assert.equal(rejected.nextPacket(), '');
  rejected.dispose();
});

test('the actual expiry timer selects an older valid cached alert, then clears every display identity field', async () => {
  const r = runtime({ testIssuer: true }); const alerts = r.create(); const now = r.now();
  const older = r.signed({ alertId: 'older', issuedAt: now - 20_000, expiresAt: now + 10_000, title: 'Older valid' });
  const newer = r.signed({ alertId: 'newer', issuedAt: now - 10_000, expiresAt: now + 2_000, title: 'Newer expiring' });
  await alerts.receive(older); await alerts.receive(newer);
  assert.equal(alerts.title, 'Newer expiring'); const priorIdentity = alerts.currentIdentity;
  r.advanceTo(newer.payload.expiresAt);
  assert.equal(alerts.received, true); assert.equal(alerts.title, 'Older valid');
  assert.equal(alerts.verificationState, 'verified'); assert.notEqual(alerts.currentIdentity, priorIdentity);
  assert.equal(alerts.issuedAt, older.payload.issuedAt); assert.equal(alerts.expiresAt, older.payload.expiresAt);
  assert.equal(alerts.allAccepted().length, 1); assert.equal(r.timers.size, 1);
  assert.equal(r.protocol.decodeEnvelope(alerts.nextPacket()).payload.alertId, 'older');
  r.advanceTo(older.payload.expiresAt);
  assert.equal(alerts.received, false); assert.equal(alerts.verificationState, 'expired');
  for (const name of ['title', 'body', 'area', 'expiry', 'issueTime', 'currentIdentity']) assert.equal(alerts[name], '', name);
  assert.equal(alerts.issuedAt, 0); assert.equal(alerts.expiresAt, 0);
  assert.equal(alerts.nextPacket(), ''); assert.equal(r.timers.size, 0);
});

test('dispose blocks timer revival by late restore, and resume reselects after expiry while hidden', async () => {
  const r = runtime({ testIssuer: true }); const store = new MemoryStore(); const now = r.now();
  const older = r.signed({ alertId: 'older', issuedAt: now - 20_000, expiresAt: now + 10_000, title: 'Still current' });
  const newer = r.signed({ alertId: 'newer', issuedAt: now - 10_000, expiresAt: now + 2_000 });
  store.values.set('relay_cache_v1', JSON.stringify([older, newer]));
  let release; const gate = new Promise(resolve => { release = resolve; });
  store.read = async key => { await gate; return store.values.get(key) || ''; };
  const alerts = r.create(store); const restore = alerts.restore(); alerts.dispose(); release(); await restore;
  assert.equal(alerts.received, true); assert.equal(r.timers.size, 0);
  r.advanceTo(now + 3_000); alerts.resume();
  assert.equal(alerts.title, 'Still current'); assert.equal(alerts.verificationState, 'verified');
  assert.equal(r.timers.size, 1); alerts.resume(); assert.equal(r.timers.size, 1);
  alerts.dispose(); alerts.dispose(); assert.equal(r.timers.size, 0);
});

test('the public lab fixture helper preserves v2 signature validity and derives only intended faults', async () => {
  const r = runtime(); const { packets } = deriveMeshLabFixtures({ now: r.now() });
  const duplicate = JSON.parse(packets.duplicate).envelope;
  assert.equal((await new r.protocol.RelayEngine().ingest(duplicate, r.now())).status, 'accepted');
  assert.equal((await new r.protocol.RelayEngine().ingest(JSON.parse(packets.tampered).envelope, r.now())).status, 'invalid');
  assert.equal((await new r.protocol.RelayEngine().ingest(JSON.parse(packets.expired).envelope, r.now())).status, 'expired');
  assert.deepEqual(duplicate.payload.translations, r.fixtures.createDemoAlert().payload.translations);
});
