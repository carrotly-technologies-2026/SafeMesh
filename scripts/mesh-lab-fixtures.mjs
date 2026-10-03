#!/usr/bin/env node
// Public, already-signed exercise fixtures only. Never signs, rotates keys or
// refreshes dates. Deterministic delivery IDs below are for fault injection only.
import { createHash, createPublicKey, verify } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function constant(source, name) {
  const match = source.match(new RegExp(`^const ${name}: SignedAlertEnvelope = (\\{[\\s\\S]*?^\\});\\s*$`, 'm'));
  if (!match) throw new Error(`DemoAlerts.ets: expected generated JSON constant ${name} is absent`);
  try { return JSON.parse(match[1]); }
  catch { throw new Error(`DemoAlerts.ets: ${name} is not the expected JSON literal`); }
}

// Same domain-separated signed fields as AlertProtocol.canonicalPayload.
function canonical(payload) {
  return JSON.stringify(['SafeMesh.Alert.v1', payload.keyId, payload.alertId,
    String(payload.revision), String(payload.issuedAt), String(payload.expiresAt),
    payload.severity, payload.area, payload.title, payload.body,
    JSON.stringify(payload.shelterIds), payload.drill ? '1' : '0', String(payload.maxHops)]);
}

/** Reads the checked-in public fixtures; importing this module writes nothing. */
export function deriveMeshLabFixtures({ root = projectRoot, now = Date.now() } = {}) {
  if (!Number.isSafeInteger(now) || now < 0) throw new Error('Invalid fixture generation time');
  const model = resolve(root, 'entry/src/main/ets/model');
  const source = readFileSync(resolve(model, 'DemoAlerts.ets'), 'utf8');
  const trust = readFileSync(resolve(model, 'DemoTrust.ets'), 'utf8');
  const keyLiteral = trust.match(/^export const DEMO_PUBLIC_KEY_DER: string = ("[A-Za-z0-9+/=]+");\s*$/m);
  const keyIdLiteral = trust.match(/^export const DEMO_KEY_ID: string = ("[^"\r\n]+");\s*$/m);
  if (!keyLiteral || !keyIdLiteral) throw new Error('DemoTrust.ets: expected public exercise key constants are absent');
  const publicKey = createPublicKey({ key: Buffer.from(JSON.parse(keyLiteral[1]), 'base64'), format: 'der', type: 'spki' });
  const keyId = JSON.parse(keyIdLiteral[1]);
  const demo = constant(source, 'DEMO_ALERT');
  const expired = constant(source, 'EXPIRED_ALERT');
  const authentic = alert => verify('sha256', Buffer.from(canonical(alert.payload)), publicKey,
    Buffer.from(alert.signature, 'base64'));
  for (const [name, alert] of [['DEMO_ALERT', demo], ['EXPIRED_ALERT', expired]]) {
    const payload = alert?.payload;
    if (!payload || payload.version !== 1 || payload.drill !== true || payload.keyId !== keyId ||
        !Number.isSafeInteger(payload.issuedAt) || !Number.isSafeInteger(payload.expiresAt) ||
        payload.expiresAt <= payload.issuedAt || !Number.isSafeInteger(payload.maxHops) || payload.maxHops < 1 ||
        typeof alert.signature !== 'string' || !authentic(alert)) {
      throw new Error(`${name}: expected an authentic signed exercise from the checked-in public authority`);
    }
  }
  const demoExpiry = new Date(demo.payload.expiresAt).toISOString();
  const expiredExpiry = new Date(expired.payload.expiresAt).toISOString();
  const generatedAt = new Date(now).toISOString();
  if (now >= demo.payload.expiresAt) {
    throw new Error(`Current demo expired at ${demoExpiry}; generation attempted ${generatedAt}. No fixtures written or dates refreshed.`);
  }
  if (now < demo.payload.issuedAt) throw new Error(`Current demo is not yet valid at ${generatedAt}; check the host clock`);
  if (now < expired.payload.expiresAt) {
    throw new Error(`Expired fixture is not yet expired: expires ${expiredExpiry}, generation attempted ${generatedAt}`);
  }
  const duplicate = structuredClone(demo); duplicate.hops = 1;
  const tampered = structuredClone(duplicate);
  tampered.payload.body = 'FORGED TEST CONTENT: changed after signing.';
  const expiredHop = structuredClone(expired); expiredHop.hops = 1;
  if (authentic(tampered)) throw new Error('Tampering fixture unexpectedly retained a valid signature');
  const packets = {};
  for (const [index, [name, envelope]] of Object.entries({ duplicate, tampered, expired: expiredHop }).entries()) {
    const packet = JSON.stringify({ type: 'safemesh.data.v1', deliveryId: String(index + 1).repeat(32), envelope });
    if (Buffer.byteLength(packet) > 9216) throw new Error(`${name}: packet exceeds the native delivery limit`);
    packets[name] = packet;
  }
  return { packets, report: { generatedAt, demoIssuedAt: new Date(demo.payload.issuedAt).toISOString(),
    demoExpiresAt: demoExpiry, expiredFixtureExpiresAt: expiredExpiry, expiredFixtureIsExpired: true,
    sourceSha256: createHash('sha256').update(source).digest('hex'),
    files: Object.keys(packets).map(name => `${name}.json`),
    note: 'Existing signatures preserved; only tampered.body and unsigned hops differ. No signing or refresh.' } };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (process.argv.length !== 2) throw new Error('Usage: node scripts/mesh-lab-fixtures.mjs');
    const { packets, report } = deriveMeshLabFixtures();
    const output = resolve(projectRoot, '.cache/mesh-lab/fixtures');
    mkdirSync(output, { recursive: true });
    for (const [name, packet] of Object.entries(packets)) writeFileSync(resolve(output, `${name}.json`), `${packet}\n`, 'utf8');
    writeFileSync(resolve(output, 'manifest.json'), `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    console.log(JSON.stringify({ output, ...report }, null, 2));
  } catch (error) {
    console.error(`Mesh lab fixture generation failed: ${error.message}`);
    process.exitCode = 1;
  }
}
