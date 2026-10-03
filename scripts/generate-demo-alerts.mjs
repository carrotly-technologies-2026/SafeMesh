import { generateKeyPairSync, sign, verify } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Exercise signer only. The ephemeral private key is never serialized or placed in the app.
// Rerunning rotates the pinned DEMO public key and all bundled exercise fixtures together.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const modelDir = resolve(root, 'entry/src/main/ets/model');
mkdirSync(modelDir, { recursive: true });
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const keyId = 'safemesh-demo-authority-v1';
const now = Date.now();
const lifetime = 72 * 60 * 60 * 1000;

function canonical(payload) {
  const fields = [
    payload.version === 2 ? 'SafeMesh.Alert.v2' : 'SafeMesh.Alert.v1', payload.keyId, payload.alertId,
    String(payload.revision), String(payload.issuedAt), String(payload.expiresAt),
    payload.severity, payload.area, payload.title, payload.body,
    JSON.stringify(payload.shelterIds), payload.drill ? '1' : '0', String(payload.maxHops)
  ];
  if (payload.version === 2) {
    fields.push(payload.language, JSON.stringify((payload.translations ?? [])
      .map(item => [item.language, item.area, item.title, item.body])));
  }
  return JSON.stringify(fields);
}

const payload = {
  version: 2, keyId, alertId: 'krakow-hackyeah-exercise-001', revision: 1,
  issuedAt: now - 60_000, expiresAt: now - 60_000 + lifetime,
  severity: 'warning', area: 'Kraków centrum',
  title: 'Przerwa w łączności',
  body: 'To ćwiczenie — do aplikacji dotarła podpisana wiadomość. Pozostaw aplikację otwartą, aby przekazać ją dalej; punkty ochronne PSP znajdziesz na mapie offline, a ich dostępność trzeba sprawdzić.',
  shelterIds: [], drill: true, maxHops: 8, language: 'pl',
  translations: [{
    language: 'en', area: 'Kraków centre', title: 'Connection outage',
    body: 'This is an exercise: a signed message has reached the app. Keep the app open to relay it; the offline map lists PSP protective points, whose current access needs checking.'
  }]
};
function envelope(body) {
  const signature = sign('sha256', Buffer.from(canonical(body)), privateKey).toString('base64');
  if (!verify('sha256', Buffer.from(canonical(body)), publicKey, Buffer.from(signature, 'base64'))) {
    throw new Error('Generated fixture signature failed self-check');
  }
  return { payload: body, signature, hops: 0 };
}
const alert = envelope(payload);
const expired = envelope({ ...payload, alertId: 'krakow-expired-exercise-001', issuedAt: now - lifetime - 3600_000, expiresAt: now - 3600_000 });
const der = publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
writeFileSync(resolve(modelDir, 'DemoTrust.ets'),
  '// Public exercise key only. This key MUST NOT authorize live emergency alerts.\n' +
  `export const DEMO_KEY_ID: string = ${JSON.stringify(keyId)};\n` +
  `export const DEMO_PUBLIC_KEY_DER: string = ${JSON.stringify(der)};\n`);
writeFileSync(resolve(modelDir, 'DemoAlerts.ets'),
  "import { SignedAlertEnvelope, copyEnvelope } from './AlertProtocol';\n" +
  "export { DEMO_KEY_ID, DEMO_PUBLIC_KEY_DER } from './DemoTrust';\n\n" +
  '// Generated signed drills. Regenerate with: node scripts/generate-demo-alerts.mjs\n' +
  `const DEMO_ALERT: SignedAlertEnvelope = ${JSON.stringify(alert, null, 2)};\n\n` +
  `const EXPIRED_ALERT: SignedAlertEnvelope = ${JSON.stringify(expired, null, 2)};\n\n` +
  'export function createDemoAlert(): SignedAlertEnvelope {\n  return copyEnvelope(DEMO_ALERT);\n}\n\n' +
  'export function createTamperedAlert(): SignedAlertEnvelope {\n  const alert: SignedAlertEnvelope = createDemoAlert();\n  alert.payload.body = "FORGED INSTRUCTION: This content was changed after signing.";\n  return alert;\n}\n\n' +
  'export function createExpiredAlert(): SignedAlertEnvelope {\n  return copyEnvelope(EXPIRED_ALERT);\n}\n');
console.log(`Created signed drill fixtures: ${new Date(payload.issuedAt).toISOString()} to ${new Date(payload.expiresAt).toISOString()}. Private key discarded.`);
