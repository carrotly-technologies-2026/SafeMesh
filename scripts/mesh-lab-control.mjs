#!/usr/bin/env node
// Local-only operator controls. No application state or alert signing here.
import { readFile } from 'node:fs/promises';

const base = 'http://127.0.0.1:8765';
const [command = 'state', ...args] = process.argv.slice(2);
const help = 'Usage: mesh-lab-control.mjs state | links AB BC | disconnect A | drop ack B A [count] | reset | apply control.json | inject A B packet.txt';
try {
  let control;
  if (command === 'state' && args.length === 0) control = undefined;
  else if (command === 'links') {
    control = { links: args.map(value => {
      if (!/^[ABC]-?[ABC]$/.test(value)) throw new Error(help);
      return value.replace('-', '').split('');
    }) };
  } else if (command === 'disconnect' && args.length > 0) control = { disconnect: args };
  else if (command === 'reset' && args.length === 0) control = { resetStats: true, dropNext: [] };
  else if (command === 'drop' && args.length >= 3 && args.length <= 4) {
    control = { dropNext: [{ kind: args[0], from: args[1], to: args[2], count: Number(args[3] ?? 1) }] };
  } else if (command === 'apply' && args.length === 1) {
    const bytes = await readFile(args[0]);
    if (bytes.length > 65536) throw new Error('Control file exceeds 64 KiB');
    control = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } else if (command === 'inject' && args.length === 3) {
    const bytes = await readFile(args[2]);
    if (bytes.length > 16384) throw new Error('Packet file exceeds 16 KiB');
    control = { inject: [{ from: args[0], to: args[1], packet: new TextDecoder('utf-8', { fatal: true }).decode(bytes) }] };
  } else throw new Error(help);
  const body = control === undefined ? undefined : JSON.stringify(control);
  if (body && Buffer.byteLength(body) > 65536) throw new Error('Encoded control exceeds 64 KiB');
  const response = await fetch(`${base}/${control === undefined ? 'state' : 'control'}`, {
    method: control === undefined ? 'GET' : 'POST',
    headers: control === undefined ? undefined : { 'Content-Type': 'application/json' },
    body, signal: AbortSignal.timeout(5000)
  });
  const result = await response.json();
  if (!response.ok) throw new Error(`Hub returned ${response.status}: ${result.error}`);
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
