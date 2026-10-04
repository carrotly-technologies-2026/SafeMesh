#!/usr/bin/env node
// Asks the local authority to sign an alert and delivers it through the mesh hub.
// If the sending node is free, this script connects as that fake emulator (default B -> A).
// If the real emulator is already connected (e.g. all of A, B and C run), the hub injects the packet
// on its behalf instead (default A -> B, which then relays to C).
// Usage: [FROM=X] [TO=Y] node scripts/oniro/send-alert.mjs "Title" "Body text" ["Area"] [info|warning|critical]
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const [title = 'Test alert', body = 'Sent from the terminal via fake emulator B.', area = 'Kraków', severity = 'warning'] =
  process.argv.slice(2);
const hub = 'http://127.0.0.1:8765';
const connected = (await (await fetch(`${hub}/state`)).json()).connected;
const inject = connected.includes(process.env.FROM ?? 'B');
const from = process.env.FROM ?? (inject ? 'A' : 'B');
const to = process.env.TO ?? (inject ? 'B' : 'A');
const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const token = readFileSync(`${repo}/.cache/demo-authority/session-token.txt`, 'utf8').trim();

const response = await fetch('http://127.0.0.1:8768/alerts', {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ requestId: randomBytes(16).toString('hex'), title, body, area, language: 'pl',
    severity, expiresInMinutes: 60 })
});
const result = await response.json();
if (!response.ok) throw new Error(`Authority returned ${response.status}: ${result.error}`);
const envelope = { ...result.envelope, hops: 1 };
const packet = JSON.stringify({ type: 'safemesh.data.v1', deliveryId: randomBytes(16).toString('hex'), envelope });

if (inject) {
  if (!connected.includes(to)) { console.error(`${to} is not connected to the hub.`); process.exit(1); }
  const injected = await fetch(`${hub}/control`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ inject: [{ from, to, packet }] }) });
  if (!injected.ok) { console.error(`Hub returned ${injected.status}: ${(await injected.json()).error}`); process.exit(1); }
  console.log(`Injected "${title}" as ${from} -> ${to}. ${to} verifies it and relays it to its other neighbors.`);
  process.exit(0);
}

const socket = new WebSocket('ws://127.0.0.1:8765/mesh');
const timer = setTimeout(() => { console.error(`Timed out: is ${to} connected to the hub?`); process.exit(1); }, 15000);
socket.onopen = () => socket.send(JSON.stringify({ type: 'hello', node: from, protocol: 1 }));
socket.onmessage = event => {
  const message = JSON.parse(event.data);
  if (message.type === 'peers') {
    if (!message.peers.includes(to)) { console.error(`${to} is not a connected neighbor of ${from}.`); process.exit(1); }
    socket.send(JSON.stringify({ type: 'send', to, packet }));
    console.log(`Sent "${title}" from ${from} to ${to}, waiting for ACK...`);
  } else if (message.type === 'packet' && message.packet.includes('safemesh.ack.v1')) {
    console.log(`${to} acknowledged the alert.`);
    clearTimeout(timer); socket.close();
  } else if (message.type === 'error') {
    console.error(`Hub error: ${message.message}`); process.exit(1);
  }
};
