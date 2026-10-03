import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes } from 'node:crypto';
import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const DEMO_KEY_ID = 'safemesh-demo-authority-v1';
export const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const DEFAULT_AUTHORITY_DIR = resolve(REPOSITORY_ROOT, '.cache/demo-authority');

// This directory must remain outside Git and all app/package inputs. On Windows,
// POSIX modes do not replace the operator's account ACL; this is a local demo key.
export function atomicPrivateWrite(filename, content) {
  const temporary = `${filename}.${randomBytes(8).toString('hex')}.tmp`;
  let descriptor;
  try {
    descriptor = openSync(temporary, 'wx', 0o600);
    writeFileSync(descriptor, content, 'utf8');
    fsyncSync(descriptor);
    closeSync(descriptor);
    descriptor = undefined;
    renameSync(temporary, filename);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
    if (existsSync(temporary)) unlinkSync(temporary);
  }
}

export function loadAuthority(directory = DEFAULT_AUTHORITY_DIR) {
  const filename = resolve(directory, 'authority.json');
  try {
    if (statSync(filename).size > 16_384) throw new Error();
    const record = JSON.parse(readFileSync(filename, 'utf8'));
    if (record.protocol !== 1 || record.keyId !== DEMO_KEY_ID ||
        typeof record.privateKeyPem !== 'string' || typeof record.token !== 'string' || !/^[a-f0-9]{64}$/.test(record.token) ||
        typeof record.publicKeyDer !== 'string') throw new Error();
    const privateKey = createPrivateKey(record.privateKeyPem);
    const publicKey = createPublicKey(privateKey);
    if (privateKey.asymmetricKeyType !== 'ec' || privateKey.asymmetricKeyDetails.namedCurve !== 'prime256v1' ||
        publicKey.export({ type: 'spki', format: 'der' }).toString('base64') !== record.publicKeyDer) throw new Error();
    return { ...record, privateKey, publicKey };
  } catch {
    throw new Error('Demo authority is missing or invalid. Run scripts/prepare-demo-authority.mjs; existing invalid material is never silently replaced.');
  }
}

export function prepareAuthority({ directory = DEFAULT_AUTHORITY_DIR, rotate = false } = {}) {
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const filename = resolve(directory, 'authority.json');
  if (existsSync(filename) && !rotate) {
    const authority = loadAuthority(directory);
    atomicPrivateWrite(resolve(directory, 'session-token.txt'), `${authority.token}\n`);
    return authority;
  }
  if (rotate && existsSync(resolve(directory, 'receipt-journal.json'))) {
    throw new Error('Explicit key rotation requires a stopped server and separately archived receipt-journal.json. Existing receipts were preserved.');
  }
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const record = {
    protocol: 1, keyId: DEMO_KEY_ID,
    publicKeyDer: publicKey.export({ type: 'spki', format: 'der' }).toString('base64'),
    privateKeyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    token: randomBytes(32).toString('hex')
  };
  atomicPrivateWrite(filename, `${JSON.stringify(record, null, 2)}\n`);
  atomicPrivateWrite(resolve(directory, 'session-token.txt'), `${record.token}\n`);
  return { ...record, privateKey, publicKey };
}

export function assertPinnedAuthority(authority, root = REPOSITORY_ROOT) {
  const trust = readFileSync(resolve(root, 'entry/src/main/ets/model/DemoTrust.ets'), 'utf8');
  const keyId = /DEMO_KEY_ID\s*:\s*string\s*=\s*"([^"]+)"/.exec(trust)?.[1];
  const publicKeyDer = /DEMO_PUBLIC_KEY_DER\s*:\s*string\s*=\s*"([^"]+)"/.exec(trust)?.[1];
  if (keyId !== authority.keyId || publicKeyDer !== authority.publicKeyDer) {
    throw new Error('Authority key differs from the app pin. Explicitly generate fixtures with --update-public-key, rebuild and reinstall the app before starting this authority.');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2);
    if (args.some(arg => arg !== '--rotate')) throw new Error('Usage: node scripts/prepare-demo-authority.mjs [--rotate]');
    const authority = prepareAuthority({ rotate: args.includes('--rotate') });
    console.log(`Local exercise authority ready. Public fingerprint SHA-256: ${createHash('sha256').update(Buffer.from(authority.publicKeyDer, 'base64')).digest('hex')}`);
    console.log(`Private material and operator token stay in ${DEFAULT_AUTHORITY_DIR}. No token is printed. Key rotation and app-pin updates are explicit.`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
