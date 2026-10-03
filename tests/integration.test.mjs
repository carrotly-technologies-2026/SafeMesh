import assert from 'node:assert/strict';
import { createPublicKey, verify } from 'node:crypto';
import { createRequire } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setImmediate as nextTurn } from 'node:timers/promises';
import vm from 'node:vm';
import test, { afterEach } from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
let ts;
try {
  ts = require('typescript');
} catch {
  const studioPath = process.env.DEVECO_CLI_STUDIO_PATH || join(process.env.USERPROFILE || '', 'DevEcoStudio');
  const bundled = process.env.ARKTS_TYPESCRIPT_PATH || join(studioPath,
    'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
  if (!existsSync(bundled)) {
    throw new Error('Set ARKTS_TYPESCRIPT_PATH to the SDK TypeScript module, or install TypeScript for host tests.');
  }
  ts = require(bundled);
}

// The actual ViewModels and protocol execute below. The platform adapters are
// replaced with Node/OpenSSL, in-memory preferences, and an observable fake radio.
// No NearLink delivery or native ArkUI/CryptoArchitectureKit is claimed by this test.
const cryptoKit = {
  cryptoFramework: {
    createAsyKeyGenerator(algorithm) {
      assert.equal(algorithm, 'ECC256');
      return { async convertKey(publicBlob, privateBlob) {
        assert.equal(privateBlob, null);
        return { pubKey: createPublicKey({ key: Buffer.from(publicBlob.data), format: 'der', type: 'spki' }) };
      } };
    },
    createVerify(algorithm) {
      assert.equal(algorithm, 'ECC256|SHA256');
      let publicKey;
      return {
        async init(key) { publicKey = key; },
        async verify(input, signature) { return verify('sha256', input.data, publicKey, signature.data); }
      };
    }
  }
};
const utilKit = { util: {
  TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } },
  Base64Helper: class { decodeSync(text) { return new Uint8Array(Buffer.from(text, 'base64')); } }
} };
const transports = [];
class TestTransport {
  constructor(callbacks) {
    this.callbacks = callbacks;
    this.sent = [];
    this.fail = false;
    transports.push(this);
  }
  async broadcast(packet, address = '') {
    if (this.fail) throw new Error('radio failure');
    this.sent.push({ packet, address });
    return 1;
  }
  async send(address, packet) {
    if (this.fail) throw new Error('radio failure');
    this.sent.push({ packet, address });
    return true;
  }
}
class TestStore {
  constructor() { this.values = new Map(); this.fail = false; this.writes = []; }
  async read(key) { return this.values.get(key) || ''; }
  async write(key, value) {
    if (this.fail) throw new Error('disk failure');
    await Promise.resolve();
    this.values.set(key, value);
    this.writes.push(key);
  }
}

const moduleCache = new Map();
function loadEts(filename) {
  const absolute = resolve(filename);
  if (moduleCache.has(absolute)) return moduleCache.get(absolute).exports;
  const module = { exports: {} };
  moduleCache.set(absolute, module);
  const output = ts.transpileModule(readFileSync(absolute, 'utf8'), {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true
    },
    fileName: absolute.replace(/\.ets$/, '.ts')
  }).outputText;
  const localRequire = specifier => {
    if (specifier === '@kit.CryptoArchitectureKit') return cryptoKit;
    if (specifier === '@kit.ArkTS') return utilKit;
    if (specifier.endsWith('/NearLinkTransport')) return { NearLinkTransport: TestTransport };
    if (specifier.startsWith('.')) return loadEts(resolve(dirname(absolute), `${specifier}.ets`));
    throw new Error(`Unexpected integration dependency: ${specifier}`);
  };
  // Observed is a UI notification decorator; identity decoration is sufficient for
  // these state/IO tests. It does not validate ArkUI's rendering reactivity.
  const execute = vm.runInThisContext(`(function(require,module,exports,Observed){${output}\n})`, { filename: absolute });
  execute(localRequire, module, module.exports, value => value);
  return module.exports;
}
const protocol = loadEts(resolve(root, 'entry/src/main/ets/model/AlertProtocol.ets'));
const fixtures = loadEts(resolve(root, 'entry/src/main/ets/model/DemoAlerts.ets'));
const { AlertViewModel } = loadEts(resolve(root, 'entry/src/main/ets/viewmodel/AlertViewModel.ets'));
const { RelayViewModel } = loadEts(resolve(root, 'entry/src/main/ets/viewmodel/RelayViewModel.ets'));
const fresh = () => fixtures.createDemoAlert();

// Deterministic exercise time is confined to this host test process. Product code
// and the emulator continue to use the real device clock and real fixture expiry.
const exerciseNow = fresh().payload.issuedAt + 60_000;
const realNow = Date.now;
Date.now = () => exerciseNow;
const views = [];
function createAlerts(store = new TestStore()) {
  const alerts = new AlertViewModel(store);
  views.push(alerts);
  return alerts;
}
afterEach(() => {
  for (const alerts of views) alerts.dispose();
  views.length = 0;
  transports.length = 0;
  Date.now = () => exerciseNow;
});
process.on('exit', () => { Date.now = realNow; });

test('a forged incoming packet preserves the authentic displayed title and badge', async () => {
  const alerts = createAlerts();
  assert.equal((await alerts.receive(fresh())).status, 'accepted');
  const title = alerts.title, badge = alerts.verification;
  assert.equal((await alerts.receive(fixtures.createTamperedAlert())).status, 'invalid');
  assert.equal(alerts.title, title);
  assert.equal(alerts.verification, badge);
  assert.equal(alerts.received, true);
  assert.match(alerts.lastReceiveStatus, /^invalid:/);
});

test('an expired incoming packet cannot replace an active verified alert', async () => {
  const alerts = createAlerts();
  await alerts.receive(fresh());
  const title = alerts.title, badge = alerts.verification;
  assert.equal((await alerts.receive(fixtures.createExpiredAlert())).status, 'expired');
  assert.equal(alerts.title, title);
  assert.equal(alerts.verification, badge);
});

test('persisted replay history restores and re-verifies before the first network packet', async () => {
  const store = new TestStore();
  await createAlerts(store).receive(fresh());
  assert.ok(store.values.get('relay_cache_v1'));
  const restored = createAlerts(store);
  assert.equal((await restored.receive(fresh())).status, 'duplicate');
  assert.equal(restored.received, true);
  assert.match(restored.persistenceStatus, /re-verified/);
  const corruptedStore = new TestStore();
  corruptedStore.values.set('verified_alert', protocol.encodeEnvelope(fixtures.createTamperedAlert()));
  const rejected = createAlerts(corruptedStore);
  await rejected.restore();
  assert.equal(rejected.received, false);
  assert.equal(rejected.nextPacket(), '');
});

test('disk failure leaves the authenticated in-memory alert intact and reports save failure', async () => {
  const store = new TestStore(); store.fail = true;
  const alerts = createAlerts(store);
  assert.equal((await alerts.receive(fresh())).status, 'accepted');
  assert.equal(alerts.received, true);
  assert.match(alerts.persistenceStatus, /save failed/);
  assert.notEqual(alerts.nextPacket(), '');
});

test('forged and malformed packets produce no outgoing radio traffic', async () => {
  const alerts = createAlerts();
  const relay = new RelayViewModel(alerts), transport = transports.at(-1);
  await relay.receive('attacker', protocol.encodeEnvelope(fixtures.createTamperedAlert()));
  await relay.receive('attacker', '{}');
  assert.equal(transport.sent.length, 0);
  assert.equal(alerts.received, false);
  assert.equal(relay.rejectedCount, 2);
});

test('a genuine arrival forwards its exact signature at hop one while excluding its sender', async () => {
  const alerts = createAlerts();
  const relay = new RelayViewModel(alerts), transport = transports.at(-1);
  await relay.receive('peer-A', protocol.encodeEnvelope(fresh()));
  assert.equal(transport.sent.length, 1);
  assert.equal(transport.sent[0].address, 'peer-A');
  const forwarded = protocol.decodeEnvelope(transport.sent[0].packet);
  assert.equal(forwarded.hops, 1);
  assert.equal(forwarded.signature, fresh().signature);
  assert.equal((await new protocol.RelayEngine().ingest(forwarded)).status, 'accepted');
});

test('concurrent arrivals forward once and busy remains set until persistence finishes', async () => {
  const alerts = createAlerts();
  const relay = new RelayViewModel(alerts), transport = transports.at(-1);
  await Promise.all([
    relay.receive('peer-A', protocol.encodeEnvelope(fresh())),
    relay.receive('peer-B', protocol.encodeEnvelope(fresh()))
  ]);
  assert.equal(transport.sent.length, 1);
  assert.equal(relay.acceptedCount, 1);
  assert.equal(alerts.busy, false);

  let release;
  let notifyBlocked;
  const gate = new Promise(resolve => { release = resolve; });
  const blocked = new Promise(resolve => { notifyBlocked = resolve; });
  const store = new TestStore();
  store.write = async (key, value) => {
    notifyBlocked();
    await gate;
    store.values.set(key, value);
  };
  const slow = createAlerts(store);
  const first = slow.receive(fresh());
  await blocked;
  assert.equal((await slow.receive(fixtures.createTamperedAlert())).status, 'invalid');
  assert.equal(slow.busy, true);
  release();
  assert.equal((await first).status, 'accepted');
  assert.equal(slow.busy, false);
});

test('fire-and-forget receive/send failures are handled without losing verified content', async () => {
  const alerts = createAlerts();
  const relay = new RelayViewModel(alerts), transport = transports.at(-1);
  transport.fail = true;
  transport.callbacks.onMessage('peer-A', protocol.encodeEnvelope(fresh()));
  await nextTurn();
  assert.equal(alerts.received, true);
  assert.match(relay.lastPacketStatus, /processing failed/);
  await assert.doesNotReject(() => relay.share());
  assert.match(relay.hardwareStatus, /send failed/);
  transport.callbacks.onPeer({ address: 'peer-B', name: 'B', connected: true });
  await nextTurn();
  assert.match(relay.hardwareStatus, /Peer send failed/);
  assert.match(alerts.verification, /Signature verified/);
});

test('exact expiry clears the displayed alert and prevents any further relay', async () => {
  const alerts = createAlerts();
  await alerts.receive(fresh());
  Date.now = () => fresh().payload.expiresAt;
  assert.equal(alerts.nextPacket(), '');
  assert.equal(alerts.received, false);
  assert.match(alerts.verification, /Expired/);
  assert.equal(alerts.expiry, '');
});
