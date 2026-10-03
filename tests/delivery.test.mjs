import assert from 'node:assert/strict';
import { createPublicKey, generateKeyPairSync, sign, verify, randomBytes } from 'node:crypto';
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
try { ts = require('typescript'); } catch {
  const studio = process.env.DEVECO_CLI_STUDIO_PATH || join(process.env.USERPROFILE || '', 'DevEcoStudio');
  const compiler = process.env.ARKTS_TYPESCRIPT_PATH || join(studio,
    'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
  if (!existsSync(compiler)) throw new Error('Set ARKTS_TYPESCRIPT_PATH or install TypeScript.');
  ts = require(compiler);
}

// A fresh TEST-ONLY trust root allows multiple genuinely signed messages without
// ever saving or using a real/exercise issuer's private key in the mobile app.
const keys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const trust = {
  DEMO_KEY_ID: 'safemesh-demo-authority-v1',
  DEMO_PUBLIC_KEY_DER: keys.publicKey.export({ format: 'der', type: 'spki' }).toString('base64')
};
const nativeCrypto = { cryptoFramework: {
  createRandom() { return { generateRandomSync(length) { return { data: new Uint8Array(randomBytes(length)) }; } }; },
  createAsyKeyGenerator(algorithm) {
    assert.equal(algorithm, 'ECC256');
    return { async convertKey(blob, privateKey) {
      assert.equal(privateKey, null);
      return { pubKey: createPublicKey({ key: Buffer.from(blob.data), format: 'der', type: 'spki' }) };
    } };
  },
  createVerify(algorithm) {
    assert.equal(algorithm, 'ECC256|SHA256');
    let key;
    return { async init(publicKey) { key = publicKey; }, async verify(data, signature) {
      return verify('sha256', data.data, key, signature.data);
    } };
  }
} };
const utilKit = { util: {
  TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
  Base64Helper: class { decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); } }
} };
const radios = [];
class Radio {
  constructor(callbacks) {
    this.callbacks = callbacks; this.sent = []; this.stopped = false;
    this.startCount = 0; this.stopCount = 0; this.discoverCount = 0;
    this.startGate = undefined; this.discoverGate = undefined;
    radios.push(this);
  }
  async send(address, packet) { this.sent.push({ address, packet }); return !this.stopped; }
  async start() { this.startCount++; if (this.startGate) await this.startGate; this.stopped = false; return true; }
  async discover() { this.discoverCount++; if (this.discoverGate) await this.discoverGate; return true; }
  async stop() { this.stopCount++; this.stopped = true; }
}
class Store {
  constructor() { this.values = new Map(); this.unavailable = false; }
  async read(key) { if (this.unavailable) throw new Error('disk unavailable'); return this.values.get(key) || ''; }
  async write(key, value) { if (this.unavailable) throw new Error('disk unavailable'); this.values.set(key, value); }
}
const modules = new Map();
function load(filename) {
  filename = resolve(filename);
  if (modules.has(filename)) return modules.get(filename).exports;
  const module = { exports: {} }; modules.set(filename, module);
  const output = ts.transpileModule(readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true },
    fileName: filename.replace(/\.ets$/, '.ts')
  }).outputText;
  const dependency = name => {
    if (name === '@kit.CryptoArchitectureKit') return nativeCrypto;
    if (name === '@kit.ArkTS') return utilKit;
    if (name.endsWith('/DemoTrust')) return trust;
    if (name.endsWith('/NearLinkTransport')) return { NearLinkTransport: Radio };
    if (name.startsWith('.')) return load(resolve(dirname(filename), `${name}.ets`));
    throw new Error(`Unexpected dependency ${name}`);
  };
  vm.runInThisContext(`(function(require,module,exports,Observed){${output}\n})`, { filename })(
    dependency, module, module.exports, value => value);
  return module.exports;
}
const model = name => resolve(root, `entry/src/main/ets/model/${name}.ets`);
const protocol = load(model('AlertProtocol'));
const codec = load(model('DeliveryProtocol'));
const { DeliveryQueue } = load(model('DeliveryQueue'));
const { AlertViewModel } = load(resolve(root, 'entry/src/main/ets/viewmodel/AlertViewModel.ets'));
const { RelayViewModel } = load(resolve(root, 'entry/src/main/ets/viewmodel/RelayViewModel.ets'));
const epoch = Date.UTC(2026, 9, 3, 15, 0);
let now = epoch;
const realNow = Date.now;
Date.now = () => now;
const alertViews = [], relayViews = [];
afterEach(async () => {
  for (const relay of relayViews) await relay.stop();
  for (const alerts of alertViews) alerts.dispose();
  alertViews.length = 0; relayViews.length = 0; radios.length = 0;
  now = epoch;
});
process.on('exit', () => { Date.now = realNow; });
function signed(id = 'alert-A', overrides = {}) {
  const payload = {
    version: 1, keyId: trust.DEMO_KEY_ID, alertId: id, revision: 1,
    issuedAt: epoch - 60_000, expiresAt: epoch + 60_000,
    severity: 'warning', area: 'Test area', title: `Exercise ${id}`, body: 'Exercise only.',
    shelterIds: [], drill: true, maxHops: 8, ...overrides
  };
  return { payload, signature: sign('sha256', Buffer.from(protocol.canonicalPayload(payload)), keys.privateKey).toString('base64'), hops: 0 };
}
async function trustedEngine(envelopes) {
  const engine = new protocol.RelayEngine();
  for (const envelope of envelopes) assert.equal((await engine.ingest(envelope)).status, 'accepted');
  return engine;
}
function queue(engine, send) {
  return new DeliveryQueue({ send, prepare(envelope) {
    const next = engine.nextHop(envelope);
    return next ? protocol.encodeEnvelope(next) : '';
  } });
}
function views(store = new Store()) {
  const alerts = new AlertViewModel(store); alertViews.push(alerts);
  const relay = new RelayViewModel(alerts); relayViews.push(relay);
  return { alerts, relay, radio: radios.at(-1), store };
}
async function peer(radio, address, connected = true) {
  radio.callbacks.onPeer({ address, name: address, connected });
  await nextTurn();
}

test('delivery codecs bound packets and never confuse acknowledgements with alerts', () => {
  const envelope = signed();
  const id = codec.createDeliveryId();
  assert.match(id, /^[a-f0-9]{32}$/);
  const packet = codec.encodeDataPacket(id, envelope);
  assert.ok(Buffer.byteLength(packet) < 16384);
  const data = codec.decodeDataPacket(packet);
  assert.equal(data.envelope.signature, envelope.signature);
  const ack = codec.makeAcknowledgement(data);
  assert.deepEqual(codec.decodeAcknowledgement(JSON.stringify(ack)), ack);
  assert.equal(protocol.decodeEnvelope(JSON.stringify(ack)), undefined);
  for (const bad of ['null', '{}', '[]', 'X'.repeat(9217)]) {
    assert.equal(codec.decodeDataPacket(bad), undefined);
    assert.equal(codec.decodeAcknowledgement(bad), undefined);
  }
  assert.equal(codec.decodeAcknowledgement(JSON.stringify({ ...ack, revision: '1' })), undefined);
});

test('all current messages enter a delayed peer queue and each pump is bounded to four writes', async () => {
  const envelopes = Array.from({ length: 9 }, (_, index) => signed(`alert-${index}`));
  const engine = await trustedEngine(envelopes), sent = [];
  const delivery = queue(engine, async (address, packet) => { sent.push({ address, packet }); return true; });
  delivery.connect('peer-B', engine.accepted());
  await delivery.flush(); assert.equal(sent.length, 4);
  await delivery.flush(); assert.equal(sent.length, 8);
  await delivery.flush(); assert.equal(sent.length, 9);
  assert.equal(new Set(sent.map(item => codec.decodeDataPacket(item.packet).envelope.payload.alertId)).size, 9);
  assert.equal(delivery.metrics().pending, 9);
  assert.ok(sent.every(item => codec.decodeDataPacket(item.packet).envelope.hops === 1));
});

test('only an expected peer, sent token, issuer, alert ID and revision can acknowledge an item', async () => {
  const envelope = signed(), engine = await trustedEngine([envelope]), sent = [];
  const delivery = queue(engine, async (address, packet) => { sent.push({ address, packet }); return true; });
  delivery.connect('B', [envelope]);
  await delivery.flush();
  const ack = codec.makeAcknowledgement(codec.decodeDataPacket(sent[0].packet));
  assert.equal(delivery.acknowledge('attacker', ack), false);
  for (const patch of [{ deliveryId: '0'.repeat(32) }, { keyId: 'other' }, { alertId: 'other' }, { revision: 2 }]) {
    assert.equal(delivery.acknowledge('B', { ...ack, ...patch }), false);
  }
  assert.equal(delivery.metrics().pending, 1);
  assert.equal(delivery.acknowledge('B', ack), true);
  assert.equal(delivery.acknowledge('B', ack), false);
  assert.equal(delivery.metrics().pending, 0);
  assert.equal(delivery.metrics().acknowledged, 1);
  assert.equal(engine.accepted().length, 1, 'ACK never deletes or trusts signed content');
  delivery.disconnect('B'); delivery.connect('B', [envelope]);
  assert.equal(delivery.acknowledge('B', ack), false, 'old-connection ACK cannot clear a new unsent token');
  await delivery.flush();
  assert.notEqual(codec.decodeDataPacket(sent[1].packet).deliveryId, ack.deliveryId);
});

test('loss uses bounded 2s/4s retries, then reports failure instead of claiming delivery', async () => {
  const envelope = signed(), engine = await trustedEngine([envelope]);
  let attempts = 0;
  const delivery = queue(engine, async () => { attempts++; return true; });
  delivery.connect('B', [envelope]);
  await delivery.flush();
  now += 1999; await delivery.flush(); assert.equal(attempts, 1);
  now += 1; await delivery.flush(); assert.equal(attempts, 2);
  now += 4000; await delivery.flush(); assert.equal(attempts, 3);
  now += 8000; await delivery.flush();
  assert.deepEqual(delivery.metrics(), { pending: 0, acknowledged: 0, retries: 2, failed: 1 });
  now += 10000; await delivery.flush(); assert.equal(attempts, 3);
  assert.equal(delivery.hasWork(), false);
});

test('a lost ACK triggers a duplicate ACK without forwarding the alert twice to the next peer', async () => {
  const envelope = signed();
  const engineA = await trustedEngine([envelope]);
  const engineB = new protocol.RelayEngine(), engineC = new protocol.RelayEngine();
  const bStatuses = []; let cAccepts = 0, droppedAck = false;
  let queueA, queueB;
  queueA = queue(engineA, async (_address, packet) => {
    const frame = codec.decodeDataPacket(packet);
    const result = await engineB.ingest(frame.envelope);
    bStatuses.push(result.status);
    if (result.status === 'accepted' || result.status === 'duplicate') queueB.queueAcknowledgement('A', codec.makeAcknowledgement(frame));
    if (result.status === 'accepted') queueB.offer(result.envelope, 'A');
    return true;
  });
  queueB = queue(engineB, async (address, packet) => {
    if (address === 'A') {
      if (!droppedAck) { droppedAck = true; return true; }
      queueA.acknowledge('B', codec.decodeAcknowledgement(packet));
    } else {
      const frame = codec.decodeDataPacket(packet);
      if ((await engineC.ingest(frame.envelope)).status === 'accepted') cAccepts++;
      queueB.acknowledge('C', codec.makeAcknowledgement(frame));
    }
    return true;
  });
  queueA.connect('B', [envelope]); queueB.connect('A', []); queueB.connect('C', []);
  await queueA.flush(); await queueB.flush();
  assert.equal(queueA.metrics().pending, 1);
  now += 2000;
  await queueA.flush(); await queueB.flush();
  assert.deepEqual(bStatuses, ['accepted', 'duplicate']);
  assert.equal(cAccepts, 1);
  assert.equal(queueA.metrics().acknowledged, 1);
  assert.equal(queueA.metrics().pending, 0);
});

test('expiry prunes pending packets and stale acknowledgements cannot revive them', async () => {
  const envelope = signed(), engine = await trustedEngine([envelope]), sent = [];
  const delivery = queue(engine, async (_address, packet) => { sent.push(packet); return true; });
  delivery.connect('B', [envelope]); await delivery.flush();
  const ack = codec.makeAcknowledgement(codec.decodeDataPacket(sent[0]));
  now = envelope.payload.expiresAt;
  assert.equal(delivery.metrics().pending, 0);
  assert.equal(delivery.acknowledge('B', ack), false);
  await delivery.flush(); assert.equal(sent.length, 1);
});

test('restored ViewModel synchronizes all messages to a late peer and re-syncs on reconnect', async () => {
  const store = new Store();
  const initial = views(store);
  for (let index = 0; index < 3; index++) await initial.alerts.receive(signed(`cached-${index}`));
  await initial.relay.stop();
  const restored = views(store);
  await peer(restored.radio, 'B');
  assert.equal(restored.radio.sent.length, 3);
  assert.equal(restored.alerts.allAccepted().length, 3);
  const frames = restored.radio.sent.map(item => codec.decodeDataPacket(item.packet));
  for (const frame of frames) await restored.relay.receive('B', JSON.stringify(codec.makeAcknowledgement(frame)));
  assert.equal(restored.relay.pendingCount, 0);
  await peer(restored.radio, 'B', false); await peer(restored.radio, 'B', true);
  assert.equal(restored.radio.sent.length, 6);
  const resent = restored.radio.sent.slice(3).map(item => codec.decodeDataPacket(item.packet));
  assert.deepEqual(resent.map(frame => frame.envelope.payload.alertId), frames.map(frame => frame.envelope.payload.alertId));
  assert.ok(resent.every((frame, index) => frame.deliveryId !== frames[index].deliveryId));
});

test('VM sends success ACK only for verified current data; duplicates ACK without re-flooding', async () => {
  const { alerts, relay, radio } = views();
  await peer(radio, 'A'); await peer(radio, 'C');
  const good = signed(), token = codec.createDeliveryId();
  const forged = structuredClone(good); forged.payload.body = 'forged';
  await relay.receive('A', codec.encodeDataPacket(token, forged));
  await relay.receive('A', codec.encodeDataPacket(token, signed('expired', { issuedAt: epoch - 120000, expiresAt: epoch - 1 })));
  await relay.receive('A', '{}');
  assert.equal(radio.sent.length, 0);
  await relay.receive('A', codec.encodeDataPacket(token, good));
  assert.equal(radio.sent.filter(item => codec.decodeAcknowledgement(item.packet)).length, 1);
  assert.equal(radio.sent.filter(item => codec.decodeDataPacket(item.packet)).length, 1);
  await relay.receive('A', codec.encodeDataPacket(token, good));
  assert.equal(radio.sent.filter(item => codec.decodeAcknowledgement(item.packet)).length, 2);
  assert.equal(radio.sent.filter(item => codec.decodeDataPacket(item.packet)).length, 1);
  assert.equal(alerts.received, true);
});

test('startup read failure blocks relay and a later successful restoration can recover', async () => {
  const store = new Store(); store.unavailable = true;
  const { alerts, relay, radio } = views(store);
  await assert.rejects(() => alerts.restore());
  await peer(radio, 'B');
  await relay.receive('A', protocol.encodeEnvelope(signed()));
  assert.equal(alerts.received, false); assert.equal(radio.sent.length, 0);
  assert.deepEqual(alerts.allAccepted(), []);
  store.unavailable = false;
  await relay.receive('A', protocol.encodeEnvelope(signed()));
  assert.equal(alerts.received, true); assert.equal(radio.sent.length, 1);
});

test('stop cancels queued work and late callbacks cannot restart radio transmission', async () => {
  const envelopes = [signed('one'), signed('two')], engine = await trustedEngine(envelopes);
  let release, count = 0;
  const gate = new Promise(resolve => { release = resolve; });
  const delivery = queue(engine, async () => { count++; await gate; return true; });
  delivery.connect('B', envelopes);
  const pending = delivery.flush(); delivery.clear(); release(); await pending;
  assert.equal(count, 1); assert.equal(delivery.metrics().pending, 0);
  const { relay, radio } = views();
  await peer(radio, 'B');
  const receiving = relay.receive('A', protocol.encodeEnvelope(signed()));
  await relay.stop(); await receiving;
  radio.callbacks.onMessage('A', protocol.encodeEnvelope(signed()));
  await peer(radio, 'C');
  assert.equal(radio.sent.length, 0); assert.equal(relay.pendingCount, 0);
});

test('queue bounds retain no more than eight peers and 128 alerts per peer', async () => {
  const envelopes = Array.from({ length: 128 }, (_, index) => signed(`bound-${index}`));
  const engine = await trustedEngine(envelopes);
  let writes = 0;
  const delivery = queue(engine, async () => { writes++; return true; });
  for (let index = 0; index < 9; index++) delivery.connect(`peer-${index}`, envelopes);
  assert.equal(delivery.metrics().pending, 8 * 128);
  await delivery.flush(); assert.equal(writes, 4);
});

test('a hung native send has a three-second app deadline and remains pending without a false receipt', async () => {
  const envelope = signed(), engine = await trustedEngine([envelope]);
  const originalSet = globalThis.setTimeout, originalClear = globalThis.clearTimeout;
  let deadline;
  globalThis.setTimeout = (callback, delay) => { assert.equal(delay, 3000); deadline = callback; return 1; };
  globalThis.clearTimeout = () => {};
  try {
    const delivery = queue(engine, async () => new Promise(() => {}));
    delivery.connect('B', [envelope]);
    const pumping = delivery.flush();
    assert.equal(typeof deadline, 'function');
    deadline();
    await pumping;
    assert.equal(delivery.metrics().pending, 1);
    assert.equal(delivery.metrics().acknowledged, 0);
    delivery.clear();
  } finally {
    globalThis.setTimeout = originalSet;
    globalThis.clearTimeout = originalClear;
  }
});

test('stop releases a hung send immediately and handles a later native rejection', async () => {
  const envelope = signed(), engine = await trustedEngine([envelope]);
  let rejectNative;
  const native = new Promise((_resolve, reject) => { rejectNative = reject; });
  const delivery = queue(engine, async () => native);
  delivery.connect('B', [envelope]);
  const pumping = delivery.flush();
  delivery.clear();
  await pumping;
  assert.equal(delivery.hasWork(), false);
  rejectNative(new Error('late native failure after stop'));
  await nextTurn();
});

test('stop during restore, native startup or discovery cannot revive foreground radio work', async () => {
  for (const phase of ['restore', 'start', 'discover']) {
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    const store = new Store();
    if (phase === 'restore') store.read = async () => { await gate; return ''; };
    const { relay, radio } = views(store);
    relay.setContext({});
    relay.peerName = 'B';
    if (phase === 'start') radio.startGate = gate;
    if (phase === 'discover') radio.discoverGate = gate;
    const starting = relay.startHardware();
    await nextTurn();
    await relay.stop();
    release();
    await starting;
    assert.equal(radio.stopped, true, phase);
    assert.equal(relay.deliveryStatus, 'stopped', phase);
    assert.equal(relay.pendingCount, 0, phase);
    assert.equal(radio.sent.length, 0, phase);
    if (phase === 'restore') assert.equal(radio.startCount, 0);
    else assert.ok(radio.stopCount >= 2, 'late native completion is cleaned up again');
  }
});
