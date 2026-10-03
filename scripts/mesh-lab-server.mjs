#!/usr/bin/env node
// Local emulator test transport, NOT NearLink or an authenticated mesh service.
// RFC 6455: bounded masked text/continuation/control frames, no extensions.
// https://www.rfc-editor.org/rfc/rfc6455 (sections 4, 5, 7, 8).
import http from 'node:http';
import { createHash, randomBytes } from 'node:crypto';
import { TextDecoder } from 'node:util';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const NODES = ['A', 'B', 'C'];
const MAX_MESSAGE = 64 * 1024;
const MAX_PACKET = 16 * 1024;
const MAX_OUTBOUND = 256 * 1024;
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const decoder = new TextDecoder('utf-8', { fatal: true });
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const knownKeys = (value, keys) => record(value) && Object.keys(value).every(key => keys.includes(key));
const nodePair = (from, to) => NODES.includes(from) && NODES.includes(to) && from !== to;
const edge = (from, to) => [from, to].sort().join('-');
const packetValid = packet => typeof packet === 'string' && packet.length > 0 &&
  Buffer.byteLength(packet, 'utf8') <= MAX_PACKET &&
  Buffer.byteLength(JSON.stringify({ type: 'packet', from: 'A', packet })) <= MAX_MESSAGE;

function frame(opcode, payload = Buffer.alloc(0)) {
  const length = payload.length;
  const header = Buffer.alloc(length < 126 ? 2 : length < 65536 ? 4 : 10);
  header[0] = 0x80 | opcode;
  if (length < 126) header[1] = length;
  else if (length < 65536) { header[1] = 126; header.writeUInt16BE(length, 2); }
  else { header[1] = 127; header.writeBigUInt64BE(BigInt(length), 2); }
  return Buffer.concat([header, payload]);
}

function packetKind(packet) {
  // Inspect only the outer delivery kind for explicit loss fixtures. No alert
  // interpretation, signature verification, modification or ACK generation.
  try {
    const type = JSON.parse(packet)?.type;
    if (type === 'safemesh.data.v1') return 'data';
    if (type === 'safemesh.ack.v1') return 'ack';
  } catch { /* An opaque non-JSON packet can still be transported. */ }
  return 'other';
}

function emptyRoutes() {
  return Object.fromEntries(NODES.flatMap(from => NODES.filter(to => to !== from).map(to =>
    [`${from}->${to}`, { attempted: 0, forwarded: 0, dropped: 0, blocked: 0, offline: 0, backpressure: 0, injected: 0 }])));
}

/** Exported for actual-socket tests. CLI always listens on loopback port 8765. */
export async function startMeshLabHub({ port = 8765, log = event => console.log(JSON.stringify(event)),
  helloTimeoutMs = 5000, heartbeatIntervalMs = 5000, heartbeatTimeoutMs = 10000 } = {}) {
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('Invalid local port');
  if ([heartbeatIntervalMs, heartbeatTimeoutMs].some(value => !Number.isInteger(value) || value < 1 || value > 2147483647)) {
    throw new Error('Invalid heartbeat interval or timeout');
  }
  let links = new Set(['A-B', 'B-C']);
  let routes = emptyRoutes();
  let dropNext = [];
  let sequence = 0;
  let actualPort = port;
  const clients = new Map();
  const connections = new Set();
  const emit = (event, details = {}) => log({ sequence: ++sequence, event, ...details });
  const state = () => ({ protocol: 1, transport: 'local-emulator-websocket', host: '127.0.0.1', port: actualPort,
    connected: [...clients.keys()].sort(), links: [...links].sort().map(value => value.split('-')),
    routes: structuredClone(routes), dropNext: structuredClone(dropNext),
    limits: { clients: 3, messageBytes: MAX_MESSAGE, packetBytes: MAX_PACKET } });

  function stop(connection, code = 1000, reason = 'closed') {
    if (connection.closed) return;
    connection.closed = true;
    clearTimeout(connection.helloTimer);
    clearTimeout(connection.heartbeatTimer);
    clearTimeout(connection.pongTimer);
    connection.pingNonce = undefined;
    connections.delete(connection);
    const node = connection.node;
    if (node && clients.get(node) === connection) clients.delete(node);
    if (!connection.socket.destroyed) {
      const payload = Buffer.alloc(2); payload.writeUInt16BE(code);
      connection.socket.end(frame(8, payload));
      const timer = setTimeout(() => connection.socket.destroy(), 500);
      timer.unref();
    }
    emit('disconnected', { node: node || null, code, reason });
    if (node) publishPeers();
  }

  function write(connection, opcode, payload) {
    if (!connection || connection.closed || connection.socket.destroyed || connection.socket.writableEnded) return false;
    const bytes = frame(opcode, payload);
    if (connection.socket.writableLength + bytes.length > MAX_OUTBOUND) {
      stop(connection, 1009, 'slow_receiver'); return false;
    }
    connection.socket.write(bytes);
    return true; // Queued to the socket, NOT a receiving-app acknowledgement.
  }

  const send = (connection, message) => write(connection, 1, Buffer.from(JSON.stringify(message)));
  const error = (connection, message) => send(connection, { type: 'error', message });
  function reject(connection, message, code = 1008) {
    error(connection, message); stop(connection, code, 'invalid_protocol');
  }
  function publishPeers() {
    for (const [node, connection] of [...clients]) {
      send(connection, { type: 'peers', peers: NODES.filter(peer => peer !== node &&
        clients.has(peer) && links.has(edge(node, peer))) });
    }
  }

  // HDC can retain a half-open reverse tunnel after the app process exits.
  // Bound that stale session so it cannot indefinitely reserve a node ID.
  function scheduleHeartbeat(connection) {
    if (connection.closed) return;
    connection.heartbeatTimer = setTimeout(() => {
      connection.heartbeatTimer = undefined;
      if (connection.closed) return;
      connection.pingNonce = randomBytes(16);
      if (!write(connection, 9, connection.pingNonce)) {
        stop(connection, 1001, 'heartbeat_write_failed'); return;
      }
      connection.pongTimer = setTimeout(() => stop(connection, 1001, 'heartbeat_timeout'), heartbeatTimeoutMs);
      connection.pongTimer.unref();
    }, heartbeatIntervalMs);
    connection.heartbeatTimer.unref();
  }

  function route(from, to, packet, faultInjection = false) {
    const counters = routes[`${from}->${to}`];
    counters.attempted++;
    if (faultInjection) counters.injected++;
    const kind = packetKind(packet);
    let outcome;
    if (!links.has(edge(from, to))) outcome = 'blocked';
    else if (!clients.has(to)) outcome = 'offline';
    else {
      const fixture = dropNext.find(rule => rule.from === from && rule.to === to &&
        (rule.kind === 'any' || rule.kind === kind) && rule.count > 0);
      if (fixture) {
        fixture.count--;
        dropNext = dropNext.filter(rule => rule.count > 0);
        outcome = 'dropped';
      } else outcome = send(clients.get(to), { type: 'packet', from, packet }) ? 'forwarded' : 'backpressure';
    }
    counters[outcome]++;
    emit('route', { from, to, kind, bytes: Buffer.byteLength(packet), outcome, faultInjection });
    // A peer/topology change can race an already queued send. This is packet
    // loss, not a sender protocol failure: only recipient ACK proves receipt.
    // Peer updates and the app retry queue handle it without closing healthy links.
    return outcome === 'forwarded';
  }

  function message(connection, payload) {
    let value;
    try { value = JSON.parse(decoder.decode(payload)); }
    catch { reject(connection, 'Expected UTF-8 JSON', 1007); return; }
    if (!connection.node) {
      if (!knownKeys(value, ['type', 'node', 'protocol']) || value.type !== 'hello' ||
          value.protocol !== 1 || !NODES.includes(value.node)) {
        reject(connection, 'Expected protocol 1 hello with node A, B or C'); return;
      }
      if (clients.has(value.node)) { reject(connection, 'Node ID is already connected'); return; }
      connection.node = value.node;
      clearTimeout(connection.helloTimer);
      clients.set(value.node, connection);
      scheduleHeartbeat(connection);
      emit('connected', { node: value.node });
      publishPeers();
      return;
    }
    if (!knownKeys(value, ['type', 'to', 'packet']) || value.type !== 'send' ||
        !nodePair(connection.node, value.to) || !packetValid(value.packet)) {
      reject(connection, 'Expected send to another node with a packet of at most 16 KiB'); return;
    }
    route(connection.node, value.to, value.packet);
  }

  function consume(connection, incoming) {
    // Bound incomplete-frame buffering even before the peer completes a header.
    if (connection.buffer.length + incoming.length > 2 * MAX_MESSAGE + 28) {
      stop(connection, 1009, 'input_buffer_limit'); return;
    }
    connection.buffer = Buffer.concat([connection.buffer, incoming]);
    while (!connection.closed && connection.buffer.length >= 2) {
      const buffer = connection.buffer;
      const first = buffer[0]; const second = buffer[1];
      const fin = (first & 0x80) !== 0; const opcode = first & 15;
      const control = opcode >= 8;
      if ((first & 0x70) !== 0 || (second & 0x80) === 0 || ![0, 1, 2, 8, 9, 10].includes(opcode)) {
        stop(connection, 1002, 'invalid_frame'); return;
      }
      if (opcode === 2) { stop(connection, 1003, 'binary_not_supported'); return; }
      let length = second & 127; let offset = 2;
      if (control && (!fin || length > 125)) { stop(connection, 1002, 'invalid_control_frame'); return; }
      if (length === 126) {
        if (buffer.length < 4) return;
        length = buffer.readUInt16BE(2); offset = 4;
        if (length < 126) { stop(connection, 1002, 'nonminimal_length'); return; }
      } else if (length === 127) {
        if (buffer.length < 10) return;
        const long = buffer.readBigUInt64BE(2); offset = 10;
        if (long >> 63n) { stop(connection, 1002, 'invalid_length'); return; }
        if (long > BigInt(MAX_MESSAGE)) { stop(connection, 1009, 'frame_limit'); return; }
        if (long < 65536n) { stop(connection, 1002, 'nonminimal_length'); return; }
        length = Number(long);
      }
      if (length > MAX_MESSAGE || (!control && connection.fragmentBytes + length > MAX_MESSAGE)) {
        stop(connection, 1009, 'message_limit'); return;
      }
      if (buffer.length < offset + 4 + length) return;
      const mask = buffer.subarray(offset, offset + 4);
      const payload = Buffer.from(buffer.subarray(offset + 4, offset + 4 + length));
      for (let index = 0; index < length; index++) payload[index] ^= mask[index & 3];
      connection.buffer = buffer.subarray(offset + 4 + length);
      if (opcode === 8) {
        if (length === 1) { stop(connection, 1002, 'invalid_close'); return; }
        if (length >= 2) {
          const code = payload.readUInt16BE();
          if (!((code >= 1000 && code <= 1014 && ![1004, 1005, 1006].includes(code)) ||
            (code >= 3000 && code <= 4999))) { stop(connection, 1002, 'invalid_close'); return; }
          try { decoder.decode(payload.subarray(2)); } catch { stop(connection, 1007, 'invalid_close_utf8'); return; }
        }
        stop(connection, 1000, 'peer_closed'); return;
      }
      if (opcode === 9) { write(connection, 10, payload); continue; }
      if (opcode === 10) {
        // Unsolicited, stale and mismatched pongs cannot extend a dead session.
        if (connection.pingNonce && payload.equals(connection.pingNonce)) {
          clearTimeout(connection.pongTimer);
          connection.pongTimer = undefined;
          connection.pingNonce = undefined;
          scheduleHeartbeat(connection);
        }
        continue;
      }
      if (opcode === 0 && !connection.fragmented || opcode === 1 && connection.fragmented) {
        stop(connection, 1002, 'invalid_fragment_sequence'); return;
      }
      if (opcode === 1 && fin) { message(connection, payload); continue; }
      if (connection.fragments.length >= 1024) { stop(connection, 1009, 'fragment_count_limit'); return; }
      connection.fragmented = true;
      connection.fragments.push(payload); connection.fragmentBytes += length;
      if (fin) {
        const combined = Buffer.concat(connection.fragments, connection.fragmentBytes);
        connection.fragments = []; connection.fragmentBytes = 0; connection.fragmented = false;
        message(connection, combined);
      }
    }
  }

  function localRequestFailure(request, websocket = false) {
    const host = request.headers.host;
    // HDC preserves the emulator URL's Host while forwarding distinct local
    // device ports to one host listener. These aliases apply ONLY to WebSocket.
    const ports = websocket ? [...new Set([actualPort, 8765, 8766, 8767])] : [actualPort];
    const allowed = ports.flatMap(value => [`127.0.0.1:${value}`, `localhost:${value}`]);
    if (!allowed.includes(host)) return 'host';
    const origin = request.headers.origin;
    // HarmonyOS API 24 WebSocket omits nonstandard ports from Origin. Accept
    // only this exact loopback spelling, matched to the already checked Host;
    // HTTP administration still requires its full matching origin with port.
    const legacyNativeOrigin = websocket && origin === `http://${host.split(':')[0]}`;
    return origin === undefined || origin === `http://${host}` || legacyNativeOrigin ? '' : 'origin';
  }

  function controlPlan(value) {
    if (!knownKeys(value, ['links', 'dropNext', 'disconnect', 'resetStats', 'inject'])) throw new Error('Invalid control fields');
    const nextLinks = value.links === undefined ? links : new Set();
    if (value.links !== undefined) {
      if (!Array.isArray(value.links) || value.links.length > 3) throw new Error('Invalid links');
      for (const pair of value.links) {
        if (!Array.isArray(pair) || pair.length !== 2 || !nodePair(...pair)) throw new Error('Invalid link');
        nextLinks.add(edge(...pair));
      }
    }
    if (value.resetStats !== undefined && typeof value.resetStats !== 'boolean') throw new Error('Invalid resetStats');
    const disconnect = value.disconnect ?? [];
    if (!Array.isArray(disconnect) || disconnect.length > 3 || disconnect.some(node => !NODES.includes(node))) {
      throw new Error('Invalid disconnect list');
    }
    const rules = value.dropNext ?? dropNext;
    if (!Array.isArray(rules) || rules.length > 18) throw new Error('Invalid dropNext list');
    for (const rule of rules) {
      if (!knownKeys(rule, ['from', 'to', 'kind', 'count']) || !nodePair(rule.from, rule.to) ||
          !['data', 'ack', 'any'].includes(rule.kind) || !Number.isInteger(rule.count) || rule.count < 1 || rule.count > 100) {
        throw new Error('Invalid drop rule');
      }
    }
    const inject = value.inject ?? [];
    if (!Array.isArray(inject) || inject.length > 16) throw new Error('Invalid injection list');
    for (const item of inject) {
      if (!knownKeys(item, ['from', 'to', 'packet']) || !nodePair(item.from, item.to) || !packetValid(item.packet) ||
          !clients.has(item.from) || !clients.has(item.to) || disconnect.includes(item.from) || disconnect.includes(item.to) ||
          !nextLinks.has(edge(item.from, item.to))) throw new Error('Injection needs connected neighbors and a bounded packet');
    }
    return { nextLinks, rules: structuredClone(rules), disconnect, inject, resetStats: value.resetStats === true };
  }

  function reply(response, status, value) {
    response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff' });
    response.end(JSON.stringify(value));
  }

  const server = http.createServer({ maxHeaderSize: 8192, headersTimeout: 5000, requestTimeout: 10000 }, async (request, response) => {
    if (localRequestFailure(request)) { reply(response, 403, { error: 'Loopback Host and same-origin requests only' }); return; }
    if (request.method === 'GET' && request.url === '/state') { reply(response, 200, state()); return; }
    if (request.method !== 'POST' || request.url !== '/control') { reply(response, 404, { error: 'Use GET /state or POST /control' }); return; }
    if (request.headers['content-type']?.split(';')[0].trim() !== 'application/json') {
      reply(response, 415, { error: 'Expected application/json' }); return;
    }
    try {
      const chunks = []; let bytes = 0;
      for await (const chunk of request) {
        bytes += chunk.length;
        if (bytes > MAX_MESSAGE) { reply(response, 413, { error: 'Control body exceeds 64 KiB' }); return; }
        chunks.push(chunk);
      }
      const plan = controlPlan(JSON.parse(decoder.decode(Buffer.concat(chunks))));
      links = plan.nextLinks; dropNext = plan.rules;
      if (plan.resetStats) routes = emptyRoutes();
      for (const node of plan.disconnect) if (clients.has(node)) stop(clients.get(node), 1000, 'control_disconnect');
      publishPeers();
      emit('control', { links: [...links].sort(), disconnect: plan.disconnect, dropRules: dropNext.length,
        resetStats: plan.resetStats, faultInjections: plan.inject.length });
      for (const item of plan.inject) route(item.from, item.to, item.packet, true);
      reply(response, 200, state());
    } catch { if (!response.headersSent) reply(response, 400, { error: 'Invalid control request' }); }
  });

  server.on('upgrade', (request, socket, head) => {
    // Restricted, bounded diagnostics: never log the key, cookies, credentials,
    // arbitrary headers, URL query or any transported alert body.
    const diagnostic = value => typeof value === 'string' ? value.slice(0, 128).replace(/[\x00-\x1f\x7f]/g, '?') : null;
    const handshake = () => ({ host: diagnostic(request.headers.host), origin: diagnostic(request.headers.origin),
      path: diagnostic(request.url?.split('?')[0]), version: diagnostic(request.headers['sec-websocket-version']) });
    const deny = (status, reason) => {
      emit('upgrade_rejected', { reason, status: Number(status.slice(0, 3)), ...handshake() });
      socket.end(`HTTP/1.1 ${status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
    };
    const localFailure = localRequestFailure(request, true);
    if (localFailure) { deny('403 Forbidden', localFailure); return; }
    const key = request.headers['sec-websocket-key'];
    if (request.method !== 'GET') { deny('400 Bad Request', 'method'); return; }
    if (!['/', '/mesh'].includes(request.url)) { deny('400 Bad Request', 'path'); return; }
    if (request.headers.upgrade?.toLowerCase() !== 'websocket' ||
        !request.headers.connection?.toLowerCase().split(',').some(value => value.trim() === 'upgrade')) {
      deny('400 Bad Request', 'upgrade'); return;
    }
    if (request.headers['sec-websocket-version'] !== '13') { deny('400 Bad Request', 'version'); return; }
    if (typeof key !== 'string' ||
        !/^[A-Za-z0-9+/]{22}==$/.test(key) || Buffer.from(key, 'base64').length !== 16) {
      deny('400 Bad Request', 'key'); return;
    }
    if (connections.size >= 3) { deny('503 Service Unavailable', 'capacity'); return; }
    const accept = createHash('sha1').update(key + GUID).digest('base64');
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    emit('upgraded', handshake());
    socket.setNoDelay(true);
    const connection = { socket, node: '', closed: false, buffer: Buffer.alloc(0), fragments: [],
      fragmentBytes: 0, fragmented: false, helloTimer: undefined,
      heartbeatTimer: undefined, pongTimer: undefined, pingNonce: undefined };
    connections.add(connection);
    connection.helloTimer = setTimeout(() => reject(connection, 'Hello timed out'), helloTimeoutMs);
    connection.helloTimer.unref();
    socket.on('data', chunk => consume(connection, chunk));
    socket.on('error', () => stop(connection, 1001, 'socket_error'));
    socket.on('close', () => stop(connection, 1001, 'socket_closed'));
    if (head.length) consume(connection, head);
  });
  server.on('clientError', (_error, socket) => socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'));
  await new Promise((done, fail) => { server.once('error', fail); server.listen(port, '127.0.0.1', done); });
  actualPort = server.address().port;
  emit('listening', { host: '127.0.0.1', port: actualPort, links: [...links].sort() });
  return { state, address: server.address(), async close() {
    for (const connection of [...connections]) {
      stop(connection, 1001, 'hub_shutdown'); connection.socket.destroy();
    }
    await new Promise((done, fail) => server.close(error => error ? fail(error) : done()));
  } };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const hub = await startMeshLabHub();
    let stopping = false;
    const stop = async () => { if (!stopping) { stopping = true; await hub.close(); } };
    process.once('SIGINT', stop); process.once('SIGTERM', stop);
  } catch (error) {
    console.error(JSON.stringify({ event: 'startup_failed', code: error.code || 'ERROR' }));
    process.exitCode = 1;
  }
}
