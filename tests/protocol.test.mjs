import assert from 'node:assert/strict';
import { createPublicKey, generateKeyPairSync, sign, verify } from 'node:crypto';
import { createRequire } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';

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

// Executes the actual ArkTS protocol source after type erasure. Only the two OS kits
// are adapted: signature operations use Node/OpenSSL and UTF-8/base64 use Node.
// This is NOT a substitute for the native CryptoArchitectureKit emulator checkpoint.
const kit = {
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
  // The API 24 emulator can return undefined for an empty input, despite the
  // SDK's Uint8Array return annotation. Preserve that native edge in host tests.
  TextEncoder: class { encodeInto(text) { return text === '' ? undefined : new TextEncoder().encode(text); } },
  Base64Helper: class { decodeSync(text) { return new Uint8Array(Buffer.from(text, 'base64')); } }
} };
const moduleCache = new Map();
function loadEts(filename) {
  const absolute = resolve(filename);
  if (moduleCache.has(absolute)) return moduleCache.get(absolute).exports;
  const module = { exports: {} };
  moduleCache.set(absolute, module);
  const output = ts.transpileModule(readFileSync(absolute, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: absolute.replace(/\.ets$/, '.ts')
  }).outputText;
  const localRequire = specifier => {
    if (specifier === '@kit.CryptoArchitectureKit') return kit;
    if (specifier === '@kit.ArkTS') return utilKit;
    if (specifier.startsWith('.')) return loadEts(resolve(dirname(absolute), `${specifier}.ets`));
    throw new Error(`Unexpected protocol dependency: ${specifier}`);
  };
  const execute = vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename: absolute });
  execute(localRequire, module, module.exports);
  return module.exports;
}
const protocol = loadEts(resolve(root, 'entry/src/main/ets/model/AlertProtocol.ets'));
const delivery = loadEts(resolve(root, 'entry/src/main/ets/model/DeliveryProtocol.ets'));
const fixtures = loadEts(resolve(root, 'entry/src/main/ets/model/DemoAlerts.ets'));
const fresh = () => fixtures.createDemoAlert();
const testNow = fresh().payload.issuedAt + 60_000;

test('empty persisted alerts and empty wire frames are rejected with the native empty-encoder behavior', () => {
  assert.equal(new utilKit.util.TextEncoder().encodeInto(''), undefined);
  assert.equal(protocol.decodeEnvelope(''), undefined);
  assert.equal(delivery.decodeDataPacket(''), undefined);
  assert.equal(delivery.decodeAcknowledgement(''), undefined);
  assert.deepEqual(protocol.decodeEnvelope(protocol.encodeEnvelope(fresh())), fresh());
});

test('real P-256 signed fixture verifies; every security-relevant field is signed', async () => {
  assert.equal((await new protocol.RelayEngine().ingest(fresh(), testNow)).status, 'accepted');
  for (const field of ['title', 'body', 'area', 'alertId', 'severity']) {
    const alert = fresh();
    alert.payload[field] = field === 'severity' ? 'critical' : `${alert.payload[field]} changed`;
    assert.equal((await new protocol.RelayEngine().ingest(alert, testNow)).status, 'invalid', field);
  }
  for (const field of ['issuedAt', 'expiresAt', 'revision']) {
    const alert = fresh(); alert.payload[field] += 1;
    const result = await new protocol.RelayEngine().ingest(alert, testNow);
    assert.notEqual(result.status, 'accepted', field);
  }
  const alert = fresh(); alert.payload.shelterIds.push('fake-shelter');
  assert.equal((await new protocol.RelayEngine().ingest(alert, testNow)).status, 'invalid');
  alert.payload.maxHops -= 1;
  assert.equal((await new protocol.RelayEngine().ingest(alert, testNow)).status, 'invalid');
});

test('v2 authenticates the original language and every alternate string, including alternate removal', async () => {
  assert.equal(fresh().payload.version, 2);
  assert.equal(fresh().payload.language, 'pl');
  assert.equal(fresh().payload.translations[0].language, 'en');
  for (const field of ['area', 'title', 'body']) {
    const alert = fresh(); alert.payload.translations[0][field] += ' changed';
    assert.equal((await new protocol.RelayEngine().ingest(alert, testNow)).status, 'invalid', field);
  }
  const removed = fresh(); delete removed.payload.translations;
  assert.equal((await new protocol.RelayEngine().ingest(removed, testNow)).status, 'invalid');
  const swapped = fresh();
  swapped.payload.language = 'en'; swapped.payload.translations[0].language = 'pl';
  assert.equal((await new protocol.RelayEngine().ingest(swapped, testNow)).status, 'invalid');
  const downgraded = fresh();
  downgraded.payload.version = 1; delete downgraded.payload.language; delete downgraded.payload.translations;
  assert.equal((await new protocol.RelayEngine().ingest(downgraded, testNow)).status, 'invalid');
});

test('malformed, duplicate, unsupported and oversized translations fail before verification', async () => {
  let verificationCalls = 0;
  const engine = new protocol.RelayEngine({ async verify() { verificationCalls++; return true; } });
  const alternate = fresh().payload.translations[0];
  for (const translations of [null, 'en', {}, [null], [false], ['en'], [[]],
    [{ ...alternate, language: 'de' }], [{ ...alternate, language: 'pl' }],
    [{ ...alternate, body: '' }], [{ ...alternate, body: false }],
    [{ ...alternate, title: 'x'.repeat(161) }], [alternate, alternate]]) {
    const alert = fresh(); alert.payload.translations = translations;
    assert.equal((await engine.ingest(alert, testNow)).status, 'invalid');
    assert.equal(protocol.decodeEnvelope(JSON.stringify(alert)), undefined);
  }
  for (const language of [null, '', 'de', 'EN', 0, undefined]) {
    const alert = fresh(); alert.payload.language = language;
    assert.equal((await engine.ingest(alert, testNow)).status, 'invalid');
  }
  const oversized = fresh();
  oversized.payload.body = '🐈'.repeat(600);
  oversized.payload.translations[0].body = '🐈'.repeat(600);
  assert.equal((await engine.ingest(oversized, testNow)).status, 'invalid');
  assert.equal(verificationCalls, 0);
});

test('v1 canonical bytes and real signature verification remain compatible; unsigned language metadata is rejected', async () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const payload = {
    version: 1, keyId: fixtures.DEMO_KEY_ID, alertId: 'legacy-v1', revision: 1,
    issuedAt: testNow - 1000, expiresAt: testNow + 1000, severity: 'info',
    area: 'Legacy area', title: 'Original title', body: 'Original signed content',
    shelterIds: ['point-1'], drill: true, maxHops: 8
  };
  // Frozen v1 field positions, independent of the implementation's v2 encoder.
  const originalBytes = JSON.stringify(['SafeMesh.Alert.v1', fixtures.DEMO_KEY_ID, 'legacy-v1',
    '1', String(testNow - 1000), String(testNow + 1000), 'info', 'Legacy area',
    'Original title', 'Original signed content', '["point-1"]', '1', '8']);
  assert.equal(protocol.canonicalPayload(payload), originalBytes);
  const alert = { payload, signature: sign('sha256', Buffer.from(originalBytes), privateKey).toString('base64'), hops: 0 };
  const verifier = { async verify(value, signature) {
    return verify('sha256', Buffer.from(protocol.canonicalPayload(value)), publicKey, Buffer.from(signature, 'base64'));
  } };
  assert.equal((await new protocol.RelayEngine(verifier).ingest(alert, testNow)).status, 'accepted');
  assert.deepEqual(protocol.decodeEnvelope(protocol.encodeEnvelope(alert)), alert);
  for (const metadata of [{ language: 'en' }, { translations: [] }, { translations: fresh().payload.translations }]) {
    const injected = structuredClone(alert); Object.assign(injected.payload, metadata);
    assert.equal((await new protocol.RelayEngine(verifier).ingest(injected, testNow)).status, 'invalid');
    assert.equal(protocol.decodeEnvelope(JSON.stringify(injected)), undefined);
  }
});

test('version 2 allows a source-only signed alert without inventing a translation', async () => {
  const sourceOnly = fresh(); delete sourceOnly.payload.translations;
  const engine = new protocol.RelayEngine({ async verify() { return true; } });
  assert.equal((await engine.ingest(sourceOnly, testNow)).status, 'accepted');
  assert.equal(engine.accepted(testNow)[0].payload.translations, undefined);
  const emptyList = structuredClone(sourceOnly); emptyList.payload.translations = [];
  assert.equal(protocol.canonicalPayload(emptyList.payload), protocol.canonicalPayload(sourceOnly.payload));
});

test('forgery cannot poison replay state; duplicate and concurrent replay suppressed', async () => {
  const relay = new protocol.RelayEngine();
  assert.equal((await relay.ingest(fixtures.createTamperedAlert(), testNow)).status, 'invalid');
  const results = await Promise.all([relay.ingest(fresh(), testNow), relay.ingest(fresh(), testNow)]);
  assert.deepEqual(results.map(result => result.status).sort(), ['accepted', 'duplicate']);
  assert.equal((await relay.ingest(fresh(), testNow)).status, 'duplicate');
  assert.equal(relay.accepted(testNow).length, 1);
});

test('demo authority can never authorize a live alert or unknown key', async () => {
  const alert = fresh(); alert.payload.drill = false;
  assert.equal((await new protocol.RelayEngine().ingest(alert, testNow)).status, 'untrusted');
  alert.payload.drill = true; alert.payload.keyId = 'untrusted';
  assert.equal((await new protocol.RelayEngine().ingest(alert, testNow)).status, 'untrusted');
});

test('expired, future, malformed, oversized and hop-exhausted messages handled', async () => {
  const relay = new protocol.RelayEngine();
  assert.equal((await relay.ingest(fixtures.createExpiredAlert(), testNow)).status, 'expired');
  assert.equal((await relay.ingest(fresh(), fresh().payload.issuedAt - 300_001)).status, 'future');
  for (const value of [null, {}, [], { payload: null }, { payload: 3 }]) {
    assert.equal((await relay.ingest(value, testNow)).status, 'invalid');
  }
  const oversized = fresh(); oversized.payload.body = 'A'.repeat(1201);
  assert.equal((await relay.ingest(oversized, testNow)).status, 'invalid');
  const overHops = fresh(); overHops.hops = overHops.payload.maxHops + 1;
  assert.equal((await relay.ingest(overHops, testNow)).status, 'hop_limit');
  const lastHop = fresh(); lastHop.hops = lastHop.payload.maxHops;
  assert.equal((await relay.ingest(lastHop, testNow)).status, 'accepted');
  assert.equal(relay.nextHop(lastHop, testNow), undefined);
  assert.equal(relay.accepted(lastHop.payload.expiresAt).length, 0);
});

test('three peers relay exact signed content offline and refuse loops', async () => {
  const peers = [new protocol.RelayEngine(), new protocol.RelayEngine(), new protocol.RelayEngine()];
  const original = fresh();
  assert.equal((await peers[0].ingest(original, testNow)).status, 'accepted');
  const first = peers[0].nextHop(original, testNow);
  assert.equal(first.hops, 1);
  assert.equal((await peers[1].ingest(first, testNow)).status, 'accepted');
  const second = peers[1].nextHop(first, testNow);
  assert.equal(second.hops, 2);
  assert.equal((await peers[2].ingest(second, testNow)).status, 'accepted');
  assert.equal(second.signature, original.signature);
  assert.equal(protocol.canonicalPayload(second.payload), protocol.canonicalPayload(original.payload));
  assert.equal((await peers[0].ingest(second, testNow)).status, 'duplicate');
  assert.equal(peers[2].nextHop(fixtures.createTamperedAlert(), testNow), undefined);
});

test('caller mutation cannot modify the authenticated cache or an in-flight candidate', async () => {
  const relay = new protocol.RelayEngine();
  const alert = fresh();
  const pending = relay.ingest(alert, testNow);
  alert.payload.body = 'changed during verification';
  alert.payload.translations[0].body = 'changed alternate during verification';
  const result = await pending;
  assert.equal(result.status, 'accepted');
  result.envelope.payload.body = 'changed result';
  relay.accepted(testNow)[0].payload.body = 'changed copy';
  result.envelope.payload.translations[0].body = 'changed result alternate';
  relay.accepted(testNow)[0].payload.translations.push({ language: 'pl', area: 'x', title: 'x', body: 'x' });
  assert.equal(relay.accepted(testNow)[0].payload.body, fresh().payload.body);
  assert.deepEqual(relay.accepted(testNow)[0].payload.translations, fresh().payload.translations);
});

test('bounded decoder rejects malformed JSON and primitive shape attacks', () => {
  assert.deepEqual(protocol.decodeEnvelope(protocol.encodeEnvelope(fresh())), fresh());
  for (const text of ['{', 'null', '[]', '{}', '0', '"string"', 'x'.repeat(8193)]) {
    assert.equal(protocol.decodeEnvelope(text), undefined);
  }
  const alert = fresh(); alert.payload.shelterIds = [false];
  assert.equal(protocol.decodeEnvelope(JSON.stringify(alert)), undefined);
  assert.throws(() => protocol.encodeEnvelope(alert));
});

test('persistence re-verifies; forged entries not restored and replays still refused', async () => {
  const before = new protocol.RelayEngine();
  await before.ingest(fresh(), testNow);
  const after = new protocol.RelayEngine();
  assert.equal(await after.restore(before.snapshot(testNow), testNow), 1);
  assert.equal((await after.ingest(fresh(), testNow)).status, 'duplicate');
  assert.equal(await after.restore(JSON.stringify([fixtures.createTamperedAlert()]), testNow), 0);
  assert.equal(await after.restore('null', testNow), 0);
  assert.equal(await after.restore('x'.repeat(128 * 8192 + 1), testNow), 0);
});

test('bounded cache fails closed; older revisions cannot replace newer alerts', async () => {
  // Policy-only injection: signature truth is tested with real crypto in tests above.
  const relay = new protocol.RelayEngine({ async verify() { return true; } });
  for (let index = 0; index < 128; index++) {
    const alert = fresh(); alert.payload.alertId = `policy-${index}`;
    assert.equal((await relay.ingest(alert, testNow)).status, 'accepted');
  }
  const extra = fresh(); extra.payload.alertId = 'policy-overflow';
  assert.equal((await relay.ingest(extra, testNow)).status, 'capacity');
  const update = fresh(); update.payload.alertId = 'policy-0'; update.payload.revision = 2;
  assert.equal((await relay.ingest(update, testNow)).status, 'accepted');
  update.payload.revision = 1;
  assert.equal((await relay.ingest(update, testNow)).status, 'duplicate');
  update.payload.revision = 3;
  update.payload.expiresAt -= 1;
  assert.equal((await relay.ingest(update, testNow)).status, 'invalid');
  assert.equal(relay.accepted(testNow).length, 128);
});
