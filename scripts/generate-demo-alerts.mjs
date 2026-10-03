import { sign, verify } from 'node:crypto';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { REPOSITORY_ROOT, assertPinnedAuthority, loadAuthority } from './prepare-demo-authority.mjs';
import { canonical } from './demo-authority-server.mjs';

// The server and bundled exercise fixtures share an operator-held local key.
// Refreshing fixtures never rotates that key or silently changes the app pin.
export function generateDemoAlerts({ root = REPOSITORY_ROOT, authority = loadAuthority(),
  now = Date.now(), updatePublicKey = false } = {}) {
  const modelDir = resolve(root, 'entry/src/main/ets/model');
  if (!updatePublicKey) {
    if (!existsSync(resolve(modelDir, 'DemoTrust.ets'))) throw new Error('Initial app pin requires --update-public-key.');
    assertPinnedAuthority(authority, root);
  }
  mkdirSync(modelDir, { recursive: true });
  const { privateKey, publicKey, keyId } = authority;
  const lifetime = 72 * 60 * 60 * 1000;

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
  return { issuedAt: payload.issuedAt, expiresAt: payload.expiresAt, publicKeyDer: der };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2);
    if (args.some(arg => arg !== '--update-public-key')) throw new Error('Usage: node scripts/generate-demo-alerts.mjs [--update-public-key]');
    const result = generateDemoAlerts({ updatePublicKey: args.includes('--update-public-key') });
    console.log(`Created signed drill fixtures: ${new Date(result.issuedAt).toISOString()} to ${new Date(result.expiresAt).toISOString()}. Private key remains only in the local authority directory.`);
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
