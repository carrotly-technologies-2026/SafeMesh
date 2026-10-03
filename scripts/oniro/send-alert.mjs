#!/usr/bin/env node
// Acts as emulator B: asks the local authority to sign an alert, then sends it to A through the mesh hub.
// Usage: node scripts/oniro/send-alert.mjs "Title" "Body text" ["Area"] [info|warning|critical]
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const [title = 'Test alert', body = 'Sent from the terminal via fake emulator B.', area = 'Kraków', severity = 'warning'] =
  process.argv.slice(2);
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

const socket = new WebSocket('ws://127.0.0.1:8765/mesh');
const timer = setTimeout(() => { console.error('Timed out: is A connected to the hub?'); process.exit(1); }, 15000);
socket.onopen = () => socket.send(JSON.stringify({ type: 'hello', node: 'B', protocol: 1 }));
socket.onmessage = event => {
  const message = JSON.parse(event.data);
  if (message.type === 'peers') {
    if (!message.peers.includes('A')) { console.error('A is not connected to the hub.'); process.exit(1); }
    socket.send(JSON.stringify({ type: 'send', to: 'A', packet }));
    console.log(`Sent "${title}" to A, waiting for ACK...`);
  } else if (message.type === 'packet' && message.packet.includes('safemesh.ack.v1')) {
    console.log('A acknowledged the alert.');
    clearTimeout(timer); socket.close();
  } else if (message.type === 'error') {
    console.error(`Hub error: ${message.message}`); process.exit(1);
  }
};
