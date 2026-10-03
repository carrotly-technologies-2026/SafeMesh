import assert from 'node:assert/strict';
import { createHash, createPublicKey, verify } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { canonical } from './demo-authority-server.mjs';

// Replay captured evidence only: no service, device, private key, or token access.
// Expiry is checked at issuance, not against replay time, so historical captures
// remain verifiable after these exercise messages have expired.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
let evidenceDirectory = resolve(root, 'artifacts/logs');
let output = resolve(evidenceDirectory, 'authority-v14-assertions.json');
const argumentsList = process.argv.slice(2);
for (let index = 0; index < argumentsList.length; index += 2) {
  const option = argumentsList[index];
  const value = argumentsList[index + 1];
  if (!value || !['--evidence-dir', '--output'].includes(option)) {
    throw new Error('Usage: node scripts/validate-authority-evidence.mjs [--evidence-dir PATH] [--output PATH]');
  }
  if (option === '--evidence-dir') evidenceDirectory = resolve(value);
  else output = resolve(value);
}

const hashes = new Map();
const checks = [];

function textFile(filename) {
  const bytes = readFileSync(filename);
  assert.ok(bytes.length <= 16 * 1024 * 1024, 'Evidence file exceeds 16 MiB');
  hashes.set(filename.startsWith(root) ? filename.slice(root.length + 1).replaceAll('\\', '/') : filename,
    createHash('sha256').update(bytes).digest('hex'));
  if (bytes[0] === 0xff && bytes[1] === 0xfe) return bytes.subarray(2).toString('utf16le');
  if (bytes[0] === 0xfe && bytes[1] === 0xff) {
    const littleEndian = Buffer.from(bytes.subarray(2));
    assert.equal(littleEndian.length % 2, 0, 'Odd UTF-16 evidence length');
    return littleEndian.swap16().toString('utf16le');
  }
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes).replace(/^\uFEFF/, '');
}

function evidence(name) {
  return textFile(resolve(evidenceDirectory, `authority-v14-${name}`));
}

function json(name) { return JSON.parse(evidence(name)); }

function nodes(value) {
  if (Array.isArray(value)) return value.flatMap(nodes);
  if (!value || typeof value !== 'object') return [];
  return [value, ...nodes(value.children ?? [])];
}

function byId(layout, id) {
  const matches = nodes(layout).filter(node => node.id === id);
  assert.equal(matches.length, 1, `Expected one UI node ${id}`);
  return matches[0];
}

function present(layout, id) { return nodes(layout).some(node => node.id === id); }
function texts(layout) { return nodes(layout).filter(node => typeof node.text === 'string').map(node => node.text); }

function pin() {
  const source = textFile(resolve(root, 'entry/src/main/ets/model/DemoTrust.ets'));
  const keyId = /DEMO_KEY_ID\s*:\s*string\s*=\s*"([^"]+)"/.exec(source)?.[1];
  const der = /DEMO_PUBLIC_KEY_DER\s*:\s*string\s*=\s*"([^"]+)"/.exec(source)?.[1];
  assert.ok(keyId && der, 'Public exercise pin is missing');
  return { keyId, der, key: createPublicKey({ key: Buffer.from(der, 'base64'), type: 'spki', format: 'der' }) };
}

function issued() {
  const envelopes = json('issued-alerts.json');
  assert.ok(Array.isArray(envelopes));
  assert.equal(envelopes.length, 2, 'Exactly two custom messages expected');
  return envelopes;
}

function signatureValid(envelope) {
  return verify('sha256', Buffer.from(canonical(envelope.payload)), pin().key,
    Buffer.from(envelope.signature, 'base64'));
}

function resources() {
  const list = JSON.parse(textFile(resolve(root, 'entry/src/main/resources/pl/element/string.json'))).string;
  return Object.fromEntries(list.map(item => [item.name, item.value]));
}

function rows(layout) {
  return nodes(layout).filter(node => /^message_authority-[a-f0-9]{32}_\d+$/.test(node.id ?? ''));
}

function assertInbox(name, envelopes, unread, banner = undefined) {
  const layout = json(name);
  const actual = rows(layout);
  assert.deepEqual(actual.map(row => row.id).sort(), envelopes.map(envelope =>
    `message_${envelope.payload.alertId}_${envelope.payload.revision}`).sort(), `${name}: inbox identities`);
  const strings = resources();
  for (const envelope of envelopes) {
    const row = byId(layout, `message_${envelope.payload.alertId}_${envelope.payload.revision}`);
    assert.ok(texts(row).includes(envelope.payload.title), `${name}: signed title missing`);
    assert.ok(texts(row).includes(envelope.payload.area), `${name}: signed area missing`);
  }
  const unreadRows = actual.filter(row => texts(row).includes(strings.unread_short));
  assert.equal(unreadRows.length, unread, `${name}: unread rows`);
  if (unread === 0) assert.equal(present(layout, 'unreadCount'), false, `${name}: stale unread badge`);
  else assert.equal(byId(layout, 'unreadCount').text, String(unread));
  if (banner !== undefined) assert.equal(present(layout, 'readIncoming'), banner, `${name}: arrival banner`);
  return layout;
}

function assertDetail(name, envelope, peer, hops) {
  const layout = json(name);
  const strings = resources();
  assert.equal(byId(layout, 'alertTitle').text, envelope.payload.title, `${name}: exact signed title`);
  assert.equal(byId(layout, 'alertBody').text, envelope.payload.body, `${name}: exact signed body`);
  assert.equal(byId(layout, 'messageArea').text, envelope.payload.area, `${name}: exact signed area`);
  assert.equal(byId(layout, 'verificationBadge').text, strings.signature_verified);
  assert.equal(byId(layout, 'messageRoute').text,
    `${strings.receipt_peer} ${peer} · ${strings.receipt_hops}: ${hops}`, `${name}: local receipt metadata`);
}

function logEvents(name, node) {
  return [...evidence(name).matchAll(/SAFEMESH_RELAY_RECEIVE node=(\S+) status=(\S+) alertId=(\S*) hops=(-?\d+)/g)]
    .filter(match => match[1] === node)
    .map(match => ({ status: match[2], alertId: match[3], hops: Number(match[4]) }));
}

function route(state, direction) {
  assert.equal(state.protocol, 1);
  assert.equal(state.transport, 'local-emulator-websocket');
  const result = state.routes?.[direction];
  assert.ok(result && ['attempted', 'forwarded', 'dropped', 'injected'].every(key =>
    Number.isSafeInteger(result[key]) && result[key] >= 0), `Missing route ${direction}`);
  return result;
}

function check(id, description, action) {
  try {
    const observations = action();
    checks.push({ id, description, passed: true, ...(observations ? { observations } : {}) });
  } catch (error) {
    checks.push({ id, description, passed: false, error: String(error.message).slice(0, 1600) });
  }
}

check('signed_custom_messages', 'Two distinct custom v2 exercises verify against the actual app public pin.', () => {
  const envelopes = issued();
  const trust = pin();
  for (const envelope of envelopes) {
    const p = envelope.payload;
    assert.equal(p.version, 2);
    assert.equal(p.keyId, trust.keyId);
    assert.match(p.alertId, /^authority-[a-f0-9]{32}$/);
    assert.equal(p.revision, 1);
    assert.equal(p.drill, true);
    assert.equal(p.language, 'pl');
    assert.deepEqual(p.translations, []);
    assert.equal(envelope.hops, 0);
    assert.ok(Number.isSafeInteger(p.issuedAt) && p.issuedAt > 0);
    assert.ok(p.expiresAt > p.issuedAt && p.expiresAt - p.issuedAt <= 24 * 60 * 60_000);
    assert.ok(Buffer.byteLength(canonical(p)) <= 4096);
    assert.equal(signatureValid(envelope), true, 'ECDSA signature failed');
  }
  for (const field of ['alertId', 'title', 'body']) assert.notEqual(envelopes[0].payload[field], envelopes[1].payload[field]);
  return { alertIds: envelopes.map(item => item.payload.alertId), publicKeySha256:
    createHash('sha256').update(Buffer.from(trust.der, 'base64')).digest('hex') };
});

check('b_map_arrival_and_unread', 'B shows arrival banners while on Map and unread counts 1 then 2.', () => {
  const envelopes = issued();
  for (const [index, name] of ['b-first-banner.json', 'b-second-banner.json'].entries()) {
    const layout = json(name);
    assert.equal(texts(layout)[0], 'Mapa');
    assert.ok(present(layout, 'offlineMap'));
    assert.ok(texts(byId(layout, 'readIncoming')).includes(envelopes[index].payload.title));
    assert.ok(texts(byId(layout, 'tab0')).includes(String(index + 1)));
  }
  assertInbox('b-first-unread.json', [envelopes[0]], 1, true);
  assertInbox('b-two-unread.json', envelopes, 2, true);
});

check('b_first_content', 'B displays the first exact signed text, valid badge, source A and hop 1.', () =>
  assertDetail('b-first-detail-pl.json', issued()[0], 'A', 1));
check('b_second_content', 'B displays the second exact signed text, valid badge, source A and hop 1.', () =>
  assertDetail('b-second-detail-pl.json', issued()[1], 'A', 1));

check('b_native_accept_and_duplicate', 'B native logs record both accepted IDs at hop 1 and the first duplicate.', () => {
  const events = logEvents('b-native-before-restart.log', 'B');
  const envelopes = issued();
  const accepted = events.filter(event => event.status === 'accepted');
  assert.equal(accepted.length, 2);
  for (const envelope of envelopes) assert.equal(accepted.filter(event =>
    event.alertId === envelope.payload.alertId && event.hops === 1).length, 1);
  assert.ok(events.some(event => event.status === 'duplicate' &&
    event.alertId === envelopes[0].payload.alertId && event.hops === 1));
});

check('lost_ack_retry', 'The first A→B delivery repeats after one dropped B→A ACK, then receives an ACK.', () => {
  const state = json('hub-first.json');
  assert.deepEqual(state.links, [['A', 'B']]);
  const data = route(state, 'A->B');
  const ack = route(state, 'B->A');
  assert.equal(data.attempted, 2);
  assert.equal(data.forwarded, 2);
  assert.equal(ack.dropped, 1);
  assert.equal(ack.forwarded, 1);
  assert.equal(route(state, 'A->C').attempted, 0);
  assert.equal(route(state, 'B->C').attempted, 0);
  return { dataAttempts: data.attempted, droppedAcks: ack.dropped, forwardedAcks: ack.forwarded };
});

check('b_read_transitions', 'Reading each B message changes unread 2→1→0 without removing either message.', () => {
  const envelopes = issued();
  const one = assertInbox('b-one-unread.json', envelopes, 1);
  assert.ok(texts(byId(one, `message_${envelopes[1].payload.alertId}_1`)).includes(resources().unread_short));
  assertInbox('b-all-read.json', envelopes, 0, false);
});

check('b_restart_durability', 'B retains both read messages after a documented process restart while the issuer is offline.', () => {
  const restart = json('b-restart.json');
  assert.match(String(restart.oldPid), /^\d+$/);
  assert.match(String(restart.newPid), /^\d+$/);
  assert.ok(Number(restart.oldPid) > 0 && Number(restart.newPid) > 0);
  assert.notEqual(String(restart.oldPid), String(restart.newPid));
  assert.equal(restart.different, true);
  assert.equal(restart.issuerOffline, true);
  assertInbox('b-restored.json', issued(), 0, false);
  return { oldPid: restart.oldPid, newPid: restart.newPid };
});

check('c_isolated_issuer_offline', 'C remains empty after both messages were issued and the issuer app/service stopped.', () => {
  const offline = json('issuer-offline.json');
  assert.equal(offline.issuerServiceStopped, true);
  assert.equal(offline.issuerAppPid, '');
  assert.ok(Date.parse(offline.utc) >= Math.max(...issued().map(item => item.payload.issuedAt)));
  for (const name of ['c-isolated.json', 'c-isolated-two-issued.json']) {
    const layout = assertInbox(name, [], 0, false);
    assert.ok(present(layout, 'emptyVerificationBadge'));
  }
});

check('bc_only_delivery', 'With A absent, only B–C is linked and both packets and ACKs traverse it; A→C stays zero.', () => {
  const state = json('hub-delivered.json');
  assert.deepEqual([...state.connected].sort(), ['B', 'C']);
  assert.deepEqual(state.links, [['B', 'C']]);
  assert.equal(route(state, 'B->C').forwarded, 2);
  assert.equal(route(state, 'C->B').forwarded, 2);
  assert.equal(route(state, 'A->C').attempted, 0);
});

check('c_two_unread', 'C receives two separate unread inbox rows and an arrival banner.', () =>
  assertInbox('c-two-unread.json', issued(), 2, true) && undefined);
check('c_first_content', 'C displays the first exact signed text, valid badge, source B and hop 2.', () =>
  assertDetail('c-first-detail.json', issued()[0], 'B', 2));
check('c_second_content', 'C displays the second exact signed text, valid badge, source B and hop 2.', () =>
  assertDetail('c-second-detail.json', issued()[1], 'B', 2));
check('c_read_transitions', 'After opening both messages, C retains both rows with no unread count or banner.', () =>
  assertInbox('c-all-read.json', issued(), 0, false) && undefined);

check('c_native_verdicts', 'C native logs contain exactly two accepted hop-2 messages, a duplicate and a rejected tamper.', () => {
  const events = logEvents('c-native.log', 'C');
  const envelopes = issued();
  const accepted = events.filter(event => event.status === 'accepted');
  assert.equal(accepted.length, 2);
  for (const envelope of envelopes) assert.equal(accepted.filter(event =>
    event.alertId === envelope.payload.alertId && event.hops === 2).length, 1);
  for (const [status, envelope] of [['duplicate', envelopes[0]], ['invalid', envelopes[1]]]) {
    assert.ok(events.some(event => event.status === status && event.alertId === envelope.payload.alertId && event.hops === 2));
  }
});

check('duplicate_ack_without_new_unread', 'A genuine duplicate produces exactly one ACK without a new row, unread mark or banner.', () => {
  const packet = json('duplicate-packet.json');
  const original = issued()[0];
  assert.equal(packet.type, 'safemesh.data.v1');
  assert.match(packet.deliveryId, /^[a-f0-9]{32}$/);
  assert.deepEqual(packet.envelope.payload, original.payload);
  assert.equal(packet.envelope.signature, original.signature);
  assert.equal(packet.envelope.hops, 2);
  assert.equal(signatureValid(packet.envelope), true);
  const before = json('hub-before-duplicate.json');
  const after = json('hub-after-duplicate.json');
  assert.equal(route(after, 'B->C').injected - route(before, 'B->C').injected, 1);
  assert.equal(route(after, 'C->B').forwarded - route(before, 'C->B').forwarded, 1);
  assert.equal(route(after, 'C->B').attempted - route(before, 'C->B').attempted, 1);
  assert.equal(route(after, 'C->A').attempted, route(before, 'C->A').attempted);
  assertInbox('c-after-duplicate.json', issued(), 0, false);
});

check('tamper_rejected_without_ack', 'Changed signed content fails crypto, receives no ACK/forward and preserves the read inbox.', () => {
  const packet = json('tampered-packet.json');
  const original = issued()[1];
  assert.equal(packet.type, 'safemesh.data.v1');
  assert.match(packet.deliveryId, /^[a-f0-9]{32}$/);
  assert.notEqual(packet.deliveryId, json('duplicate-packet.json').deliveryId);
  assert.equal(packet.envelope.signature, original.signature);
  assert.equal(packet.envelope.hops, 2);
  assert.notEqual(packet.envelope.payload.body, original.payload.body);
  assert.deepEqual({ ...packet.envelope.payload, body: original.payload.body }, original.payload);
  assert.equal(signatureValid(packet.envelope), false);
  const before = json('hub-before-tampered.json');
  const after = json('hub-after-tampered.json');
  assert.equal(route(after, 'B->C').injected - route(before, 'B->C').injected, 1);
  for (const direction of ['C->B', 'C->A']) {
    assert.equal(route(after, direction).attempted, route(before, direction).attempted);
    assert.equal(route(after, direction).forwarded, route(before, direction).forwarded);
  }
  const layout = assertInbox('c-after-tampered.json', issued(), 0, false);
  assert.equal(texts(layout).some(text => text.includes(packet.envelope.payload.body)), false);
  assertDetail('c-second-detail-after-tampered.json', original, 'B', 2);
});

const passed = checks.filter(item => item.passed).length;
const report = {
  schemaVersion: 1,
  checkedAtUtc: new Date().toISOString(),
  kind: 'replay-of-captured-native-emulator-evidence',
  scope: 'Two custom signed exercises: authority A → citizen B → citizen C through a loopback WebSocket lab.',
  passed: passed === checks.length,
  counts: { passed, failed: checks.length - passed, total: checks.length },
  checks,
  evidenceSha256: Object.fromEntries([...hashes.entries()].sort(([left], [right]) => left.localeCompare(right))),
  limitations: [
    'This script replays saved UI trees, native logs and hub counters; it does not operate devices or repeat the live scenario.',
    'UI receipt peer and hop count are local metadata, not a cryptographically authenticated route.',
    'ACK records receiving-app receipt, not human reading. Reading is checked separately through captured inbox UI.',
    'The cryptographic check uses the current app public pin and the backend canonical implementation. No private credentials are read.',
    'This is exercise-authority and emulator transport evidence, not official emergency-authority or physical-radio validation.'
  ]
};
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`);
console.log(`Authority evidence: ${passed}/${checks.length} PASS. Report: ${output}`);
for (const check of checks.filter(item => !item.passed)) console.error(`FAIL ${check.id}: ${check.error}`);
if (!report.passed) process.exitCode = 1;
