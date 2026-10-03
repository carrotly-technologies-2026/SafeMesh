import assert from 'node:assert/strict';
import test from 'node:test';
import net from 'node:net';
import http from 'node:http';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { startMeshLabHub } from '../scripts/mesh-lab-server.mjs';

async function lab(t, options = {}) {
  const events = [];
  const hub = await startMeshLabHub({ port: 0, log: event => events.push(event), ...options });
  t.after(() => hub.close());
  return { hub, events, url: `http://127.0.0.1:${hub.address.port}` };
}

function inbox() {
  const queue = []; const waiting = [];
  return {
    queue,
    push(value) {
      const index = waiting.findIndex(item => item.match(value));
      if (index < 0) queue.push(value);
      else { const [item] = waiting.splice(index, 1); clearTimeout(item.timer); item.resolve(value); }
    },
    take(match) {
      const index = queue.findIndex(match);
      if (index >= 0) return Promise.resolve(queue.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const item = { match, resolve, timer: setTimeout(() => {
          waiting.splice(waiting.indexOf(item), 1); reject(new Error('Socket message timed out'));
        }, 2000) };
        waiting.push(item);
      });
    }
  };
}

async function peer(hub, node, path = '/mesh') {
  const messages = inbox(); const closed = inbox();
  const socket = new WebSocket(`ws://127.0.0.1:${hub.address.port}${path}`);
  socket.addEventListener('message', event => messages.push(JSON.parse(event.data)));
  socket.addEventListener('close', event => closed.push(event));
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', () => reject(new Error('WebSocket open failed')), { once: true });
  });
  const result = { socket, messages, closed, send: value => socket.send(JSON.stringify(value)),
    next: type => messages.take(value => value.type === type) };
  if (node) {
    result.send({ type: 'hello', node, protocol: 1 });
    const answer = await messages.take(value => ['peers', 'error'].includes(value.type));
    result.initial = answer;
  }
  return result;
}

async function control(url, value, headers = {}) {
  const response = await fetch(`${url}/control`, { method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(value) });
  return { status: response.status, body: await response.json() };
}

async function rawHttp(url, headers) {
  return new Promise((resolve, reject) => {
    const request = http.request(new URL('/control', url), { method: 'POST', headers }, response => {
      response.resume(); response.on('end', () => resolve(response.statusCode));
    });
    request.on('error', reject); request.end('{}');
  });
}

async function eventually(predicate) {
  const deadline = Date.now() + 2000;
  while (!predicate() && Date.now() < deadline) await delay(10);
  assert.ok(predicate(), 'Expected socket-side state before deadline');
}

test('real WebSocket peers enforce A-B-C topology and forward unchanged opaque packets without alert logs', async t => {
  const { hub, events, url } = await lab(t);
  const a = await peer(hub, 'A', '/'); assert.deepEqual(a.initial.peers, []);
  const b = await peer(hub, 'B'); assert.deepEqual(b.initial.peers, ['A']);
  const c = await peer(hub, 'C'); assert.deepEqual(c.initial.peers, ['B']);
  assert.deepEqual((await b.messages.take(value => value.type === 'peers' && value.peers.length === 2)).peers, ['A', 'C']);
  const opaque = 'opaque-not-JSON: SECRET-ALERT-BODY';
  a.send({ type: 'send', to: 'B', packet: opaque });
  assert.deepEqual(await b.next('packet'), { type: 'packet', from: 'A', packet: opaque });
  a.send({ type: 'send', to: 'C', packet: opaque });
  await eventually(() => hub.state().routes['A->C'].blocked === 1);
  const state = await (await fetch(`${url}/state`)).json();
  assert.equal(state.routes['A->B'].forwarded, 1); assert.equal(state.routes['A->C'].blocked, 1);
  assert.deepEqual(c.messages.queue.filter(value => value.type === 'packet'), []);
  assert.deepEqual(a.messages.queue.filter(value => value.type === 'error'), []);
  assert.equal(JSON.stringify({ state, events }).includes('SECRET-ALERT-BODY'), false);
});

test('topology controls update neighbors, offline sends have no hub backlog, and disconnect releases role', async t => {
  const { hub, url } = await lab(t);
  const a = await peer(hub, 'A'); const b = await peer(hub, 'B');
  const offline = 'sent-while-C-offline';
  b.send({ type: 'send', to: 'C', packet: offline });
  await eventually(() => hub.state().routes['B->C'].offline === 1);
  assert.deepEqual(b.messages.queue.filter(value => value.type === 'error'), []);
  const c = await peer(hub, 'C');
  assert.deepEqual(c.messages.queue.filter(value => value.type === 'packet'), []);
  assert.equal((await control(url, { links: [['A', 'C']], disconnect: ['B'] })).status, 200);
  assert.deepEqual((await a.messages.take(value => value.type === 'peers' && value.peers.includes('C'))).peers, ['C']);
  assert.equal((await b.closed.take(() => true)).code, 1000);
  a.send({ type: 'send', to: 'C', packet: 'now-connected' });
  assert.equal((await c.next('packet')).packet, 'now-connected');
  const again = await peer(hub, 'B'); assert.deepEqual(again.initial.peers, []);
});

test('a stale-peer send after topology loss does not disconnect the healthy sender or its other neighbor', async t => {
  const { hub, url } = await lab(t);
  const a = await peer(hub, 'A'); const b = await peer(hub, 'B'); await peer(hub, 'C');
  await control(url, { links: [['A', 'B']] });
  // Model a send already in flight while the B-C topology update arrives.
  b.send({ type: 'send', to: 'C', packet: 'stale-peer-packet' });
  await eventually(() => hub.state().routes['B->C'].blocked === 1);
  b.send({ type: 'send', to: 'A', packet: 'healthy-link-packet' });
  assert.equal((await a.next('packet')).packet, 'healthy-link-packet');
  assert.deepEqual(hub.state().connected, ['A', 'B', 'C']);
  assert.deepEqual(b.messages.queue.filter(value => value.type === 'error'), []);
  assert.equal(b.socket.readyState, WebSocket.OPEN);
  assert.equal(hub.state().routes['B->C'].forwarded, 0);
});

test('duplicate roles, invalid hello and fourth connections cannot replace real peers', async t => {
  const { hub } = await lab(t);
  const a = await peer(hub, 'A');
  const duplicate = await peer(hub, 'A');
  assert.equal(duplicate.initial.type, 'error');
  assert.equal((await duplicate.closed.take(() => true)).code, 1008);
  const invalid = await peer(hub);
  invalid.send({ type: 'hello', node: 'D', protocol: 1 });
  assert.equal((await invalid.next('error')).type, 'error');
  await invalid.closed.take(() => true);
  await peer(hub, 'B'); await peer(hub, 'C');
  await assert.rejects(peer(hub), /open failed/);
  assert.deepEqual(hub.state().connected, ['A', 'B', 'C']);
  assert.equal(a.socket.readyState, WebSocket.OPEN);
});

test('explicit drop fixtures count data/ACK loss and never synthesize acknowledgements', async t => {
  const { hub, url } = await lab(t);
  const a = await peer(hub, 'A'); const b = await peer(hub, 'B');
  const data = JSON.stringify({ type: 'safemesh.data.v1', envelope: 'opaque' });
  const ack = JSON.stringify({ type: 'safemesh.ack.v1', deliveryId: 'opaque' });
  await control(url, { dropNext: [{ from: 'A', to: 'B', kind: 'data', count: 1 },
    { from: 'B', to: 'A', kind: 'ack', count: 1 }] });
  a.send({ type: 'send', to: 'B', packet: data }); a.send({ type: 'send', to: 'B', packet: data });
  assert.equal((await b.next('packet')).packet, data);
  b.send({ type: 'send', to: 'A', packet: ack }); b.send({ type: 'send', to: 'A', packet: ack });
  assert.equal((await a.next('packet')).packet, ack);
  const state = hub.state();
  assert.equal(state.routes['A->B'].dropped, 1); assert.equal(state.routes['A->B'].forwarded, 1);
  assert.equal(state.routes['B->A'].dropped, 1); assert.equal(state.routes['B->A'].forwarded, 1);
  assert.deepEqual(state.dropNext, []);
  assert.deepEqual(a.messages.queue.filter(value => value.type === 'packet'), []);
});

test('fault injection is explicit, counted and opaque; invalid control is atomic', async t => {
  const { hub, url, events } = await lab(t);
  await peer(hub, 'A'); const b = await peer(hub, 'B');
  const packet = '{"invalidAlert":"SECRET-FAULT-BODY"}';
  assert.equal((await control(url, { inject: [{ from: 'A', to: 'B', packet }] })).status, 200);
  assert.equal((await b.next('packet')).packet, packet);
  assert.equal(hub.state().routes['A->B'].injected, 1);
  assert.equal(events.find(value => value.event === 'route').faultInjection, true);
  assert.equal(JSON.stringify(events).includes('SECRET-FAULT-BODY'), false);
  const before = hub.state();
  assert.equal((await control(url, { links: [], resetStats: true, inject: [{ from: 'A', to: 'B', packet }] })).status, 400);
  assert.deepEqual(hub.state(), before);
  assert.equal((await control(url, { inject: [{ from: 'A', to: 'C', packet }] })).status, 400);
});

test('UTF-8 packet limits and hello deadline close only the offending client', async t => {
  const { hub } = await lab(t, { helloTimeoutMs: 100 });
  const idle = await peer(hub); await idle.next('error');
  assert.equal((await idle.closed.take(() => true)).code, 1008);
  const a = await peer(hub, 'A'); const b = await peer(hub, 'B');
  a.send({ type: 'send', to: 'B', packet: 'ą'.repeat(8192) });
  assert.equal(Buffer.byteLength((await b.next('packet')).packet), 16384);
  a.send({ type: 'send', to: 'B', packet: 'ą'.repeat(8193) });
  await a.next('error'); assert.equal((await a.closed.take(() => true)).code, 1008);
  assert.deepEqual(hub.state().connected, ['B']);
});

test('HTTP control requires local Host, same origin and JSON; body and topology are bounded', async t => {
  const { hub, url } = await lab(t);
  assert.equal((await control(url, {}, { Origin: 'https://untrusted.example' })).status, 403);
  // Fetch normalizes Host, so use the actual HTTP wire to exercise DNS-rebind rejection.
  assert.equal(await rawHttp(url, { Host: 'untrusted.example', 'Content-Type': 'application/json' }), 403);
  assert.equal((await control(url, {}, { 'Content-Type': 'text/plain' })).status, 415);
  assert.equal((await control(url, { links: [['A', 'A']] })).status, 400);
  assert.equal((await control(url, { dropNext: [{ from: 'A', to: 'B', kind: 'ack', count: -1 }] })).status, 400);
  assert.equal((await control(url, { unexpected: true })).status, 400);
  const response = await fetch(`${url}/control`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ padding: 'x'.repeat(65536) }) });
  assert.equal(response.status, 413);
  assert.deepEqual(hub.state().links, [['A', 'B'], ['B', 'C']]);
});

function clientFrame(opcode, text, { fin = true, mask = true, rsv = 0 } = {}) {
  const payload = Buffer.isBuffer(text) ? text : Buffer.from(text);
  const size = payload.length;
  const header = Buffer.alloc(size < 126 ? 2 : size < 65536 ? 4 : 10);
  header[0] = (fin ? 128 : 0) | rsv | opcode;
  header[1] = (mask ? 128 : 0) | (size < 126 ? size : size < 65536 ? 126 : 127);
  if (size >= 126 && size < 65536) header.writeUInt16BE(size, 2);
  if (size >= 65536) header.writeBigUInt64BE(BigInt(size), 2);
  if (!mask) return Buffer.concat([header, payload]);
  const masking = Buffer.from([1, 2, 3, 4]);
  const copy = Buffer.from(payload); for (let i = 0; i < copy.length; i++) copy[i] ^= masking[i & 3];
  return Buffer.concat([header, masking, copy]);
}

async function rawPeer(hub, headers = {}) {
  const socket = net.connect(hub.address.port, '127.0.0.1');
  const frames = inbox(); let buffer = Buffer.alloc(0); let upgraded = false;
  socket.on('error', () => {});
  socket.on('data', chunk => {
    buffer = Buffer.concat([buffer, chunk]);
    if (!upgraded) {
      const end = buffer.indexOf('\r\n\r\n'); if (end < 0) return;
      assert.match(buffer.subarray(0, end).toString(), /^HTTP\/1.1 101 /);
      buffer = buffer.subarray(end + 4); upgraded = true;
    }
    while (buffer.length >= 2) {
      let length = buffer[1] & 127; let offset = 2;
      if (length === 126) { if (buffer.length < 4) return; length = buffer.readUInt16BE(2); offset = 4; }
      else if (length === 127) { if (buffer.length < 10) return; length = Number(buffer.readBigUInt64BE(2)); offset = 10; }
      if (buffer.length < offset + length) return;
      frames.push({ opcode: buffer[0] & 15, payload: Buffer.from(buffer.subarray(offset, offset + length)) });
      buffer = buffer.subarray(offset + length);
    }
  });
  await once(socket, 'connect');
  const fields = { Host: `127.0.0.1:${hub.address.port}`, Upgrade: 'websocket', Connection: 'Upgrade',
    'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': 'dGhlIHNhbXBsZSBub25jZQ==', ...headers };
  socket.write(`GET /mesh HTTP/1.1\r\n${Object.entries(fields).map(([name, value]) => `${name}: ${value}`).join('\r\n')}\r\n\r\n`);
  return { socket, frames };
}

async function rejectedUpgrade(hub, headers = {}, path = '/mesh') {
  const socket = net.connect(hub.address.port, '127.0.0.1');
  const fields = { Host: `127.0.0.1:${hub.address.port}`, Upgrade: 'websocket', Connection: 'Upgrade',
    'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': 'dGhlIHNhbXBsZSBub25jZQ==', ...headers };
  await once(socket, 'connect');
  const response = once(socket, 'data');
  socket.write(`GET ${path} HTTP/1.1\r\n${Object.entries(fields).map(([name, value]) => `${name}: ${value}`).join('\r\n')}\r\n\r\n`);
  const [data] = await response; socket.destroy();
  return Number(data.toString().split(' ')[1]);
}

test('HDC WebSocket aliases 8765/8766/8767 accept matching origins without permitting HTTP administration', async t => {
  const { hub, url } = await lab(t);
  for (const [index, port] of [8765, 8766, 8767].entries()) {
    const host = `127.0.0.1:${port}`;
    const client = await rawPeer(hub, { Host: host, Origin: `http://${host}` });
    client.socket.write(clientFrame(1, JSON.stringify({ type: 'hello', node: ['A', 'B', 'C'][index], protocol: 1 })));
    assert.equal(JSON.parse((await client.frames.take(value => value.opcode === 1)).payload).type, 'peers');
    assert.equal(await rawHttp(url, { Host: host, 'Content-Type': 'application/json' }), 403);
  }
  assert.deepEqual(hub.state().connected, ['A', 'B', 'C']);
});

test('WebSocket aliases reject unrelated ports/origins and diagnostics exclude secrets and query strings', async t => {
  const { hub, events } = await lab(t);
  const privateHeaders = { Authorization: 'Bearer SECRET-TOKEN', Cookie: 'SECRET-COOKIE' };
  assert.equal(await rejectedUpgrade(hub, { Host: '127.0.0.1:8768', ...privateHeaders }), 403);
  assert.equal(await rejectedUpgrade(hub, { Host: '127.0.0.1:8766', Origin: 'http://127.0.0.1:8767' }), 403);
  assert.equal(await rejectedUpgrade(hub, { Origin: 'https://untrusted.example' }), 403);
  assert.equal(await rejectedUpgrade(hub, {}, '/other?token=SECRET-QUERY'), 400);
  assert.equal(await rejectedUpgrade(hub, { 'Sec-WebSocket-Version': '12' }), 400);
  const rejected = events.filter(value => value.event === 'upgrade_rejected');
  assert.deepEqual(rejected.map(value => value.reason), ['host', 'origin', 'origin', 'path', 'version']);
  assert.equal(rejected[3].path, '/other');
  for (const entry of rejected) assert.deepEqual(Object.keys(entry).sort(),
    ['sequence', 'event', 'reason', 'status', 'host', 'origin', 'path', 'version'].sort());
  assert.equal(JSON.stringify(events).includes('SECRET'), false);
  assert.equal(JSON.stringify(events).includes('dGhlIHNhbXBsZSBub25jZQ'), false);
});

test('HarmonyOS API24 portless loopback Origin works only for matching WebSocket Host, never HTTP admin', async t => {
  const { hub, url } = await lab(t);
  for (const [index, hostname] of ['127.0.0.1', 'localhost', '127.0.0.1'].entries()) {
    const client = await rawPeer(hub, { Host: `${hostname}:${8765 + index}`, Origin: `http://${hostname}` });
    client.socket.write(clientFrame(1, JSON.stringify({ type: 'hello', node: ['A', 'B', 'C'][index], protocol: 1 })));
    assert.equal(JSON.parse((await client.frames.take(value => value.opcode === 1)).payload).type, 'peers');
  }
  assert.deepEqual(hub.state().connected, ['A', 'B', 'C']);
  assert.equal(await rejectedUpgrade(hub, { Host: '127.0.0.1:8766', Origin: 'http://localhost' }), 403);
  assert.equal(await rejectedUpgrade(hub, { Host: 'localhost:8767', Origin: 'http://127.0.0.1' }), 403);
  assert.equal(await rawHttp(url, { Host: `127.0.0.1:${hub.address.port}`, Origin: 'http://127.0.0.1',
    'Content-Type': 'application/json' }), 403);
});

test('RFC6455 masked fragmented text and interleaved ping work across TCP chunk boundaries', async t => {
  const { hub } = await lab(t);
  const client = await rawPeer(hub);
  const first = clientFrame(1, '{"type":"hello",', { fin: false });
  client.socket.write(first.subarray(0, 1)); await delay(10); client.socket.write(first.subarray(1));
  client.socket.write(clientFrame(9, 'probe'));
  client.socket.write(clientFrame(0, '"node":"A","protocol":1}'));
  assert.equal((await client.frames.take(value => value.opcode === 10)).payload.toString(), 'probe');
  assert.deepEqual(JSON.parse((await client.frames.take(value => value.opcode === 1)).payload), { type: 'peers', peers: [] });
  assert.deepEqual(hub.state().connected, ['A']);
});

test('RFC6455 rejects unmasked, binary, reserved-bit, malformed control and invalid UTF-8 frames', async t => {
  const { hub } = await lab(t);
  const cases = [
    [clientFrame(1, '{}', { mask: false }), 1002],
    [clientFrame(2, 'binary'), 1003],
    [clientFrame(1, '{}', { rsv: 64 }), 1002],
    [clientFrame(9, 'ping', { fin: false }), 1002],
    [clientFrame(0, 'unexpected continuation'), 1002],
    [clientFrame(8, Buffer.from([0])), 1002],
    [clientFrame(1, Buffer.from([0xc0, 0xaf])), 1007]
  ];
  for (const [bytes, expected] of cases) {
    const client = await rawPeer(hub); client.socket.write(bytes);
    const closed = await client.frames.take(value => value.opcode === 8);
    assert.equal(closed.payload.readUInt16BE(), expected);
    client.socket.destroy();
  }
});

test('RFC6455 oversized frame declaration and cumulative fragment size fail without unbounded allocation', async t => {
  const { hub } = await lab(t);
  const first = await rawPeer(hub);
  const header = Buffer.alloc(10); header[0] = 129; header[1] = 255; header.writeBigUInt64BE(65537n, 2);
  first.socket.write(header);
  assert.equal((await first.frames.take(value => value.opcode === 8)).payload.readUInt16BE(), 1009);
  first.socket.destroy();
  const second = await rawPeer(hub);
  second.socket.write(clientFrame(1, 'x'.repeat(40000), { fin: false }));
  second.socket.write(clientFrame(0, 'x'.repeat(30000)));
  assert.equal((await second.frames.take(value => value.opcode === 8)).payload.readUInt16BE(), 1009);
  second.socket.destroy();
});

test('RFC6455 empty-fragment floods have a bounded fragment count', async t => {
  const { hub } = await lab(t);
  const client = await rawPeer(hub);
  const chunks = [clientFrame(1, '', { fin: false })];
  for (let index = 0; index < 1024; index++) chunks.push(clientFrame(0, '', { fin: false }));
  client.socket.write(Buffer.concat(chunks));
  assert.equal((await client.frames.take(value => value.opcode === 8)).payload.readUInt16BE(), 1009);
  client.socket.destroy();
});

test('heartbeat reaps a silent session, publishes peer loss and releases its role without dropping healthy apps', async t => {
  const { hub, events } = await lab(t, { heartbeatIntervalMs: 60, heartbeatTimeoutMs: 180 });
  const a = await peer(hub, 'A');
  const silent = await rawPeer(hub);
  silent.socket.write(clientFrame(1, JSON.stringify({ type: 'hello', node: 'B', protocol: 1 })));
  await silent.frames.take(value => value.opcode === 1);
  await peer(hub, 'C');
  const ping = await silent.frames.take(value => value.opcode === 9);
  assert.equal(ping.payload.length, 16);
  assert.equal((await silent.frames.take(value => value.opcode === 8)).payload.readUInt16BE(), 1001);
  assert.deepEqual(hub.state().connected, ['A', 'C']);
  assert.deepEqual((await a.messages.take(value => value.type === 'peers' && value.peers.length === 0)).peers, []);
  assert.deepEqual(events.filter(value => value.reason === 'heartbeat_timeout').map(value => value.node), ['B']);
  const replacement = await peer(hub, 'B');
  assert.deepEqual(replacement.initial.peers, ['A', 'C']);
  // Ordinary WebSocket clients automatically pong and survive several deadlines.
  await delay(400);
  assert.deepEqual(hub.state().connected, ['A', 'B', 'C']);
  assert.equal(replacement.socket.readyState, WebSocket.OPEN);
  assert.equal(events.filter(value => value.reason === 'heartbeat_timeout').length, 1);
  silent.socket.destroy();
});

test('only the outstanding heartbeat nonce is acknowledged; stale, unrelated pongs and data cannot keep a session alive', async t => {
  const { hub, events } = await lab(t, { heartbeatIntervalMs: 50, heartbeatTimeoutMs: 180 });
  const client = await rawPeer(hub);
  client.socket.write(clientFrame(1, JSON.stringify({ type: 'hello', node: 'A', protocol: 1 })));
  await client.frames.take(value => value.opcode === 1);
  client.socket.write(clientFrame(10, 'unsolicited'));
  const first = await client.frames.take(value => value.opcode === 9);
  client.socket.write(clientFrame(10, first.payload));
  const second = await client.frames.take(value => value.opcode === 9);
  assert.notDeepEqual(second.payload, first.payload);
  assert.deepEqual(hub.state().connected, ['A']);
  client.socket.write(clientFrame(10, first.payload));
  client.socket.write(clientFrame(10, 'unrelated'));
  client.socket.write(clientFrame(1, JSON.stringify({ type: 'send', to: 'B', packet: 'not-a-pong' })));
  assert.equal((await client.frames.take(value => value.opcode === 8)).payload.readUInt16BE(), 1001);
  assert.deepEqual(hub.state().connected, []);
  assert.equal(hub.state().routes['A->B'].offline, 1);
  assert.equal(events.filter(value => value.reason === 'heartbeat_timeout').length, 1);
  client.socket.destroy();
});

test('hub shutdown cancels an outstanding heartbeat without delayed disconnect activity', async t => {
  const events = []; let closed = false;
  const hub = await startMeshLabHub({ port: 0, log: event => events.push(event),
    heartbeatIntervalMs: 30, heartbeatTimeoutMs: 100 });
  t.after(async () => { if (!closed) await hub.close(); });
  const client = await rawPeer(hub);
  client.socket.write(clientFrame(1, JSON.stringify({ type: 'hello', node: 'A', protocol: 1 })));
  await client.frames.take(value => value.opcode === 9);
  await hub.close(); closed = true;
  const snapshot = structuredClone(events);
  await delay(180);
  assert.deepEqual(events, snapshot);
  assert.deepEqual(events.filter(value => value.event === 'disconnected').map(value => value.reason), ['hub_shutdown']);
  client.socket.destroy();
});
