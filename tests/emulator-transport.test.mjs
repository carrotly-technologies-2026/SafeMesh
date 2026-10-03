import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

// Execute the production adapter. Only native Kit import, sockets and timers are mocked.
const source = readFileSync(new URL('../entry/src/main/ets/transport/EmulatorTransport.ets', import.meta.url), 'utf8');
assert(source.includes("import { webSocket } from '@kit.NetworkKit'"));
const javascript = stripTypeScriptTypes(source.replace(/^import[^\n]+\n/gm, ''), { mode: 'strip' })
  .replace(/export /g, '');
const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const flush = async () => { for (let index = 0; index < 12; index++) await Promise.resolve(); };

function harness(options = {}) {
  const state = { sockets: [], statuses: [], peers: [], messages: [], errors: [], logs: [] };
  const timers = new Map();
  let timerId = 0;
  let now = 0;
  class Socket {
    listeners = new Map();
    captured = new Map();
    sent = [];
    sendResults = [];
    closes = 0;
    offCalls = [];
    on(type, callback) { this.listeners.set(type, callback); this.captured.set(type, callback); }
    off(type) {
      this.offCalls.push(type);
      this.listeners.delete(type);
      if (options.offThrows) throw new Error('unsubscribe failed');
    }
    connect(url) { this.url = url; return options.connectResult ?? Promise.resolve(true); }
    send(text) {
      this.sent.push(text);
      return this.sendResults.shift() ?? Promise.resolve(true);
    }
    close() { this.closes++; return options.closeResult ?? Promise.resolve(true); }
    emit(type, value) {
      const callback = this.listeners.get(type);
      if (!callback) return;
      if (type === 'error') callback(value);
      else callback(undefined, value);
    }
    message(value) { this.emit('message', typeof value === 'string' ? value : JSON.stringify(value)); }
  }
  const kit = { webSocket: { createWebSocket() {
    const socket = new Socket(); state.sockets.push(socket); return socket;
  } } };
  const Adapter = new Function('webSocket', 'setTimeout', 'clearTimeout', 'console', javascript + '\nreturn EmulatorTransport;')(
    kit.webSocket,
    (callback, duration) => { const id = ++timerId; timers.set(id, { callback, at: now + duration }); return id; },
    id => timers.delete(id),
    { info: message => state.logs.push(message), error: message => state.logs.push(message) }
  );
  const adapter = new Adapter({
    onStatus: status => { state.statuses.push(status); options.onStatus?.(status); },
    onPeer: peer => state.peers.push(peer),
    onMessage: (from, packet) => state.messages.push({ from, packet }),
    onError: (operation, code, message) => {
      state.errors.push({ operation, code, message }); options.onError?.(operation, code, message);
    }
  }, options.node ?? 'A');
  const advance = async milliseconds => {
    now += milliseconds;
    for (const [id, entry] of [...timers]) {
      if (entry.at <= now && timers.delete(id)) entry.callback();
    }
    await flush();
  };
  const open = async () => {
    const starting = adapter.start({});
    await flush();
    const socket = state.sockets.at(-1);
    socket.emit('open', { status: 101 });
    await flush();
    return { starting, socket };
  };
  const ready = async (peers = ['B']) => {
    const result = await open();
    result.socket.message({ type: 'peers', peers });
    assert.equal(await result.starting, true);
    await flush();
    return result.socket;
  };
  return { state, adapter, timers, advance, open, ready };
}

test('probing the lab neither creates a native socket nor fabricates peers; invalid roles cannot connect', async () => {
  const app = harness();
  const status = await app.adapter.probe();
  assert.equal(status.state, 'lab_disconnected');
  assert.equal(status.supported, true); // Availability of test mode, not evidence of a radio.
  assert.match(status.message, /No NearLink radio/);
  assert.equal(app.state.sockets.length, 0);
  assert.equal(app.state.peers.length, 0);
  assert.equal(await app.adapter.discover('anything'), false);
  assert.equal(await app.adapter.connect('B'), false);
  const invalid = harness({ node: 'D' });
  assert.equal(await invalid.adapter.start({}), false);
  assert.equal(invalid.state.sockets.length, 0);
  assert.equal(invalid.state.statuses.at(-1).state, 'lab_error');
});

test('start is shared and readiness requires open plus the server peer handshake', async () => {
  const app = harness();
  const starting = app.adapter.start({});
  assert.equal(app.adapter.start({}), starting);
  let completed = false;
  starting.then(() => { completed = true; });
  await flush();
  assert.equal(app.state.sockets.length, 1);
  const socket = app.state.sockets[0];
  assert.equal(socket.url, 'ws://127.0.0.1:8765/mesh');
  assert.equal(completed, false);
  assert.equal(socket.sent.length, 0);
  socket.emit('open', { status: 101 });
  await flush();
  assert.deepEqual(JSON.parse(socket.sent[0]), { type: 'hello', node: 'A', protocol: 1 });
  assert.equal(completed, false);
  assert.equal(await app.adapter.send('B', 'packet'), false);
  socket.message({ type: 'peers', peers: [] });
  assert.equal(await starting, true);
  assert.equal(app.state.statuses.at(-1).state, 'lab_ready');
  assert.equal(app.state.statuses.at(-1).connectedPeers, 0);
  assert.equal(app.state.peers.length, 0);
  assert.equal(await app.adapter.discover('ignored'), true);
  assert.equal(app.timers.size, 0);
  await app.adapter.stop();
});

test('only topology peers are emitted, and removed or unknown senders cannot deliver packets', async () => {
  const app = harness({ node: 'B' });
  const socket = await app.ready(['A', 'C']);
  assert.equal(socket.url, 'ws://127.0.0.1:8766/mesh');
  assert.deepEqual(app.state.peers.map(peer => [peer.address, peer.connected]), [['A', true], ['C', true]]);
  socket.message({ type: 'peers', peers: ['A', 'C'] });
  assert.equal(app.state.peers.length, 2);
  assert.equal(await app.adapter.connect('A'), true);
  assert.equal(await app.adapter.connect('B'), false);
  assert.equal(await app.adapter.connect('D'), false);
  socket.message({ type: 'packet', from: 'A', packet: 'original signed bytes' });
  assert.deepEqual(app.state.messages, [{ from: 'A', packet: 'original signed bytes' }]);
  socket.message({ type: 'peers', peers: ['C'] });
  assert.deepEqual(app.state.peers.at(-1), { address: 'A', name: 'Lab A', rssi: 127,
    connectable: false, connected: false, mtu: 16384 });
  socket.message({ type: 'packet', from: 'A', packet: 'stale neighbor' });
  socket.message({ type: 'packet', from: 'D', packet: 'unknown sender' });
  assert.equal(app.state.messages.length, 1);
  assert.equal(await app.adapter.send('A', 'stale route'), false);
  assert.equal(await app.adapter.send('C', 'opaque packet'), true);
  assert.deepEqual(JSON.parse(socket.sent.at(-1)), { type: 'send', to: 'C', packet: 'opaque packet' });
  assert.equal(app.state.messages.length, 1, 'WebSocket writes do not fabricate an application ACK');
  await app.adapter.stop();
});

test('each fixed emulator role uses its own reverse port and diagnostics exclude packet contents', async () => {
  for (const [node, port] of [['A', 8765], ['B', 8766], ['C', 8767]]) {
    const app = harness({ node });
    const peer = node === 'B' ? 'A' : 'B';
    const socket = await app.ready([peer]);
    assert.equal(socket.url, `ws://127.0.0.1:${port}/mesh`);
    const packet = 'private alert body must not appear in logs';
    await app.adapter.send(peer, packet);
    socket.emit('error', { code: 2302999, message: 'Native connection error\n' + 'x'.repeat(500) });
    assert(app.state.logs.some(line => line.includes(`node=${node} event=open`)));
    const failure = app.state.logs.find(line => line.includes('event=fail'));
    assert.match(failure, /op=socket code=2302999/);
    assert.match(failure, /Native connection error/);
    assert.equal(failure.includes('\n'), false);
    assert(failure.length < 360);
    assert.equal(app.state.logs.some(line => line.includes(packet)), false);
    await flush();
  }
});

test('outgoing and incoming packet limits count UTF-8 bytes, and JSON expansion is bounded separately', async () => {
  const app = harness();
  const socket = await app.ready();
  for (const packet of ['x'.repeat(16384), 'ł'.repeat(8192), '🛟'.repeat(4096)]) {
    assert.equal(await app.adapter.send('B', packet), true);
    assert.equal(JSON.parse(socket.sent.at(-1)).packet, packet);
    socket.message({ type: 'packet', from: 'B', packet });
    assert.equal(app.state.messages.at(-1).packet, packet);
  }
  const accepted = app.state.messages.length;
  for (const packet of ['', 'x'.repeat(16385), 'ł'.repeat(8193), '🛟'.repeat(4097), '\0'.repeat(16384)]) {
    assert.equal(await app.adapter.send('B', packet), false);
  }
  for (const packet of ['', 'ł'.repeat(8193), '🛟'.repeat(4097)]) {
    socket.message({ type: 'packet', from: 'B', packet });
  }
  assert.equal(app.state.messages.length, accepted);
  assert.equal(app.state.statuses.at(-1).state, 'lab_ready');
  await app.adapter.stop();
});

test('malformed, extra-field and invalid peer handshakes fail closed without partially accepting peers', async () => {
  const frames = ['null', '[]', '42', '{broken', JSON.stringify({ type: 'peers', peers: ['B', 'B'] }),
    JSON.stringify({ type: 'peers', peers: ['B', 'A'] }), JSON.stringify({ type: 'peers', peers: [1] }),
    JSON.stringify({ type: 'peers', peers: ['B'], extra: true }), JSON.stringify({ type: 'peers', peers: ['D'] }),
    JSON.stringify({ type: 'peers', peers: ['B', 'C', 'D'] }), JSON.stringify({ type: 'peers', peers: null }),
    JSON.stringify({ type: 'unknown' }), ' '.repeat(65537), '🛟'.repeat(16385)];
  for (const frame of frames) {
    const app = harness();
    const { starting, socket } = await app.open();
    socket.message(frame);
    assert.equal(await starting, false, frame.slice(0, 80));
    assert.equal(app.state.peers.length, 0);
    assert.equal(app.state.statuses.at(-1).state, 'lab_error');
    assert.equal(socket.closes, 1);
    assert.equal(socket.listeners.size, 0);
    await flush();
    assert.equal(app.timers.size, 0);
  }
});

test('binary frames and packets before a completed handshake cannot bypass the protocol', async () => {
  const app = harness();
  const { starting, socket } = await app.open();
  socket.message({ type: 'packet', from: 'B', packet: 'before peers' });
  assert.equal(app.state.messages.length, 0);
  socket.emit('message', new Uint8Array([123, 125]).buffer);
  assert.equal(await starting, false);
  assert.equal(app.state.statuses.at(-1).state, 'lab_error');
  await flush();
});

test('stop cancels an in-flight write, detaches handlers, emits peer losses and ignores late callbacks', async () => {
  const app = harness({ offThrows: true });
  const old = await app.ready();
  const pending = deferred();
  old.sendResults.push(pending.promise);
  const sending = app.adapter.send('B', 'pending');
  await app.adapter.stop();
  assert.equal(await sending, false);
  assert.equal(app.state.peers.at(-1).connected, false);
  assert.equal(app.state.statuses.at(-1).state, 'lab_disconnected');
  assert.deepEqual(old.offCalls, ['open', 'message', 'close', 'error']);
  assert.equal(app.timers.size, 0);
  const current = await app.ready(['C']);
  const snapshot = JSON.stringify(app.state.statuses);
  old.captured.get('open')(undefined, { status: 101 });
  old.captured.get('message')(undefined, JSON.stringify({ type: 'peers', peers: ['B'] }));
  old.captured.get('message')(undefined, JSON.stringify({ type: 'packet', from: 'B', packet: 'late' }));
  old.captured.get('close')(undefined, { code: 1000, reason: 'old' });
  old.captured.get('error')({ code: 1 });
  pending.resolve(true);
  await flush();
  assert.equal(JSON.stringify(app.state.statuses), snapshot);
  assert.equal(app.state.messages.length, 0);
  assert.equal(await app.adapter.send('C', 'current'), true);
  assert.equal(current.closes, 0);
  await app.adapter.stop();
});

test('stop during a deferred native connect settles start and prevents late connection revival', async () => {
  const gate = deferred();
  const app = harness({ connectResult: gate.promise });
  const starting = app.adapter.start({});
  await flush();
  const socket = app.state.sockets[0];
  await app.adapter.stop();
  assert.equal(await starting, false);
  gate.resolve(true);
  socket.captured.get('open')(undefined, { status: 101 });
  socket.captured.get('message')(undefined, JSON.stringify({ type: 'peers', peers: ['B'] }));
  await flush();
  assert.equal(app.state.sockets.length, 1);
  assert.equal(socket.closes, 1);
  assert.equal(socket.sent.length, 0);
  assert.equal(app.state.peers.length, 0);
  assert.equal(app.state.statuses.at(-1).state, 'lab_disconnected');
  assert.equal(app.timers.size, 0);
});

test('handshake and send deadlines settle callers; cleanup remains bounded if native close never resolves', async () => {
  const noConnect = harness({ connectResult: deferred().promise, closeResult: deferred().promise });
  const first = noConnect.adapter.start({});
  await flush();
  await noConnect.advance(10000);
  assert.equal(await first, false);
  assert.equal(noConnect.state.statuses.at(-1).state, 'lab_error');
  await noConnect.advance(1000);
  assert.equal(noConnect.timers.size, 0);
  const noHandshake = harness();
  const { starting } = await noHandshake.open();
  await noHandshake.advance(10000);
  assert.equal(await starting, false);
  const blocked = harness({ closeResult: deferred().promise });
  const socket = await blocked.ready();
  socket.sendResults.push(deferred().promise);
  const sending = blocked.adapter.send('B', 'pending forever');
  await blocked.advance(5000);
  assert.equal(await sending, false);
  assert.equal(blocked.state.statuses.at(-1).state, 'lab_error');
  await blocked.advance(1000);
  assert.equal(blocked.timers.size, 0);
  const closing = harness({ closeResult: deferred().promise });
  await closing.ready();
  const stopped = closing.adapter.stop();
  await closing.advance(1000);
  await stopped;
});

test('hub rejection, failed native connect and close events report truthful disconnected state', async () => {
  const rejected = harness({ connectResult: Promise.resolve(false) });
  assert.equal(await rejected.adapter.start({}), false);
  assert.equal(rejected.state.statuses.at(-1).state, 'lab_error');
  const app = harness();
  const { starting, socket } = await app.open();
  socket.message({ type: 'error', message: 'Node is already connected.' });
  assert.equal(await starting, false);
  assert.equal(app.state.errors.at(-1).operation, 'hub');
  assert.equal(app.state.statuses.at(-1).state, 'lab_error');
  const connected = harness();
  const active = await connected.ready();
  active.emit('close', { code: 1000, reason: 'hub shutdown' });
  assert.equal(connected.state.statuses.at(-1).state, 'lab_disconnected');
  assert.equal(connected.state.statuses.at(-1).connectedPeers, 0);
  assert.equal(connected.state.peers.at(-1).connected, false);
  assert.equal(await connected.adapter.send('B', 'after close'), false);
  await flush();
});

test('fatal errors preserve the final diagnostic after peer cleanup and a reconnect clears the old failure', async () => {
  const closeGate = deferred();
  const display = { state: '', detail: '', peers: 0 };
  // Observe the same single status/detail surface consumed by RelayViewModel.
  const app = harness({ closeResult: closeGate.promise,
    onStatus: status => {
      display.state = status.state; display.detail = status.message; display.peers = status.connectedPeers;
    },
    onError: (operation, code, message) => {
      display.state = 'lab_error'; display.detail = `${operation}: ${message} (${code})`;
    }
  });
  const old = await app.ready(['B']);
  old.emit('error', { code: 2302999, message: 'Connection rejected by the local endpoint' });
  await flush();
  assert.equal(display.state, 'lab_error');
  assert.equal(display.peers, 0);
  assert.match(display.detail, /Connection rejected by the local endpoint \(2302999\)$/);
  assert.equal(app.state.peers.at(-1).connected, false);
  assert.equal(await app.adapter.discover('ignored'), false);
  assert.equal(await app.adapter.connect('B'), false);
  assert.equal(await app.adapter.send('B', 'after error'), false);
  assert.equal(old.listeners.size, 0);

  // Retry can start while the obsolete native socket is still being closed.
  const recovery = await app.open();
  assert.equal(display.state, 'lab_connecting');
  assert.equal(display.detail.includes('Connection rejected'), false);
  recovery.socket.message({ type: 'peers', peers: ['C'] });
  assert.equal(await recovery.starting, true);
  assert.equal(display.state, 'lab_ready');
  assert.equal(display.peers, 1);
  assert.equal(display.detail.includes('2302999'), false);
  closeGate.resolve(true);
  old.captured.get('error')({ code: 1, message: 'late old error' });
  old.captured.get('close')(undefined, { code: 1000 });
  await flush();
  assert.equal(display.state, 'lab_ready');
  assert.equal(display.detail.includes('late old error'), false);
  assert.equal(await app.adapter.send('C', 'new session'), true);
  await app.adapter.stop();
  assert.equal(app.timers.size, 0);
});
