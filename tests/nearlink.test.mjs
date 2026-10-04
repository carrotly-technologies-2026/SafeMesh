import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { setImmediate as nextTurn } from 'node:timers/promises';

// Run against the actual application source. Only platform radio/permission APIs are mocked.
const require = createRequire(import.meta.url);
const studioRoots = [
  process.env.DEVECO_CLI_STUDIO_PATH,
  path.join(os.homedir(), 'DevEcoStudio'),
  'C:/Program Files/Huawei/DevEco Studio',
  '/Applications/DevEco-Studio.app/Contents'
].filter(Boolean);
const compilerPath = studioRoots
  .map(root => path.join(root,
    'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'))
  .find(candidate => fs.existsSync(candidate));

if (!compilerPath) {
  throw new Error('DevEco SDK TypeScript compiler not found. Set DEVECO_CLI_STUDIO_PATH to the DevEco Studio installation directory.');
}

const ts = require(compilerPath);
const sourcePath = fileURLToPath(new URL('../entry/src/harmonyos/transport/NearLinkTransport.ets', import.meta.url));
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  fileName: 'NearLinkTransport.ts'
}).outputText;

const ADDRESS = 'AA:BB:CC:DD:EE:FF';
const UUID = 'A39B6D32-81C4-4DA8-B730-D2E0629A7441';
const MESSAGE = JSON.stringify({
  message: 'Zażółć gęślą jaźń 🛟 '.repeat(80),
  signature: 'transport-test-fixture-not-an-authority-signature'
});

function makeHarness({ capable = true, permissionGranted = true, apiVersion = 24, hardware = true } = {}) {
  const state = {
    capable, permissionGranted, importCount: 0, permissionRequests: 0,
    writes: [], messages: [], errors: [], statuses: [], peers: [], scanFilters: [],
    listeners: new Map(), deferredTimers: [], touchedBindings: new Set(),
    portsCreated: 0, advertisements: 0, stoppedAdvertisements: [], disconnects: [],
    permissionGate: undefined, advertisingGate: undefined, connectGate: undefined, writeGate: undefined
  };
  const on = (name, callback) => state.listeners.set(name, callback);
  const off = name => state.listeners.delete(name);
  const kit = {
    manager: {
      // Declared from API 23; older systems do not expose the function at all.
      isNearLinkSupported: apiVersion >= 23 ? () => hardware : undefined,
      getState: () => 1,
      NearlinkState: { STATE_ON: 1 }
    },
    advertising: {
      startAdvertising: async () => { state.advertisements++; if (state.advertisingGate) await state.advertisingGate; return 7; },
      stopAdvertising: async id => { state.stoppedAdvertisements.push(id); }
    },
    scan: {
      on, off,
      startScan: async filters => { state.scanFilters.push(filters); },
      stopScan: async () => {},
      ScanMode: { SCAN_MODE_LOW_POWER: 0 }
    },
    dataTransfer: {
      createPort: () => { state.portsCreated++; }, destroyPort: () => {}, on, off,
      connect: async () => { if (state.connectGate) await state.connectGate; },
      disconnect: async params => { state.disconnects.push(params.address); },
      TransferMode: { RELIABLE: 1 },
      writeData: async params => { state.writes.push(new Uint8Array(params.data).slice()); if (state.writeGate) await state.writeGate; }
    }
  };
  class Encoder {
    encodeInto(value) { return value === '' ? undefined : new TextEncoder().encode(value); }
  }
  const util = {
    TextEncoder: Encoder,
    TextDecoder: {
      create: () => ({ decodeToString: input => new TextDecoder('utf-8', { fatal: true }).decode(input) })
    }
  };
  const sandbox = {
    exports: {},
    require(name) {
      if (name === '@kit.ArkTS') return { util };
      if (name === '@kit.BasicServicesKit') return { deviceInfo: { sdkApiVersion: apiVersion } };
      if (name === '@kit.AbilityKit') {
        return {
          abilityAccessCtrl: {
            createAtManager: () => ({
              requestPermissionsFromUser: async () => {
                state.permissionRequests++;
                if (state.permissionGate) await state.permissionGate;
                return { authResults: [state.permissionGranted ? 0 : -1] };
              }
            })
          }
        };
      }
      if (name === '@kit.NearLinkKit') {
        // CommonJS erases ArkTS lazy-import syntax. This proxy models binding
        // access only; the real ArkTS compiler/runtime validates native loading.
        return new Proxy(kit, { get(target, key) {
          if (!state.touchedBindings.has(key)) { state.touchedBindings.add(key); state.importCount++; }
          return target[key];
        } });
      }
      throw new Error(`Unexpected platform module: ${name}`);
    },
    canIUse: () => state.capable,
    setTimeout(callback, milliseconds) {
      if (milliseconds === 10) callback(); // Avoid real pacing delays in deterministic host tests.
      else state.deferredTimers.push(callback);
      return state.deferredTimers.length;
    },
    clearTimeout(id) { state.deferredTimers[id - 1] = undefined; },
    console, Uint8Array, DataView, Map, Set, Promise, Date
  };
  vm.runInNewContext(compiled, sandbox, { filename: sourcePath });
  const radio = new sandbox.exports.NearLinkTransport({
    onStatus: status => state.statuses.push(status),
    onPeer: peer => state.peers.push(peer),
    onMessage: (address, packet) => state.messages.push({ address, packet }),
    onError: (operation, code, message) => state.errors.push({ operation, code, message })
  });
  function discoverPeer() {
    state.listeners.get('deviceFound')([{
      address: ADDRESS, rssi: -55, data: new ArrayBuffer(0),
      deviceName: 'TestPhone', isConnectable: true
    }]);
  }
  function confirmConnection(mtu = 127) {
    state.listeners.get('connectionStateChanged')({ address: ADDRESS, uuid: UUID, mtu, state: 1 });
  }
  function receive(bytes) {
    state.listeners.get('readData')({ address: ADDRESS, uuid: UUID, data: bytes.slice().buffer });
  }
  return { state, radio, discoverPeer, confirmConnection, receive };
}

async function connectedHarness() {
  const harness = makeHarness();
  assert.equal(await harness.radio.start({}), true);
  harness.discoverPeer();
  assert.equal(await harness.radio.connect(ADDRESS), true);
  harness.confirmConnection();
  return harness;
}

function joinWrites(writes) {
  const joined = new Uint8Array(writes.reduce((length, chunk) => length + chunk.length, 0));
  let offset = 0;
  for (const chunk of writes) {
    joined.set(chunk, offset);
    offset += chunk.length;
  }
  return joined;
}

test('unsupported emulator neither imports NearLink Kit nor fabricates peers', async () => {
  const { radio, state } = makeHarness({ capable: false });
  assert.equal((await radio.probe()).state, 'unsupported');
  assert.equal(await radio.start({}), false);
  assert.equal(state.importCount, 0);
  assert.equal(state.permissionRequests, 0);
  assert.equal(radio.connectedCount(), 0);
  assert.equal(state.peers.length, 0);
  const denied = makeHarness({ permissionGranted: false });
  assert.equal(await denied.radio.start({}), false);
  assert.equal(denied.state.statuses.at(-1).state, 'permission-denied');
});

test('discovery requires a nonempty valid exact name filter', async () => {
  const { radio, state } = makeHarness();
  assert.equal(await radio.discover('TestPhone'), false);
  assert.equal(await radio.start({}), true);
  assert.equal(await radio.discover('  '), false);
  assert.equal(await radio.discover('x'.repeat(31)), false);
  assert.equal(await radio.discover('  TestPhone  '), true);
  assert.equal(state.scanFilters.length, 1);
  assert.equal(state.scanFilters[0][0].deviceName, 'TestPhone');
});

test('peer is counted only after an SDK connection callback', async () => {
  const harness = makeHarness();
  assert.equal(await harness.radio.start({}), true);
  harness.discoverPeer();
  assert.equal(harness.radio.connectedCount(), 0);
  assert.equal(await harness.radio.connect(ADDRESS), true);
  assert.equal(harness.radio.connectedCount(), 0);
  assert.equal(await harness.radio.send(ADDRESS, MESSAGE), false);
  harness.confirmConnection();
  assert.equal(harness.radio.connectedCount(), 1);
});

test('MTU-sized writes and arbitrary 7-byte reads preserve UTF-8 packets', async () => {
  const harness = await connectedHarness();
  assert.equal(await harness.radio.send(ADDRESS, MESSAGE), true);
  assert(harness.state.writes.length > 1);
  assert(harness.state.writes.every(chunk => chunk.length <= 127));
  const frame = joinWrites(harness.state.writes);
  for (let offset = 0; offset < frame.length; offset += 7) {
    harness.receive(frame.slice(offset, offset + 7));
  }
  assert.equal(harness.state.messages.length, 1);
  assert.equal(harness.state.messages[0].packet, MESSAGE);
  assert.equal(harness.state.messages[0].address, ADDRESS);
});

test('coalesced frames are decoded as separate messages', async () => {
  const harness = await connectedHarness();
  assert.equal(await harness.radio.send(ADDRESS, MESSAGE), true);
  const frame = joinWrites(harness.state.writes);
  const coalesced = new Uint8Array(frame.length * 2);
  coalesced.set(frame);
  coalesced.set(frame, frame.length);
  harness.receive(coalesced);
  assert.equal(harness.state.messages.length, 2);
  assert.equal(harness.state.messages[0].packet, MESSAGE);
  assert.equal(harness.state.messages[1].packet, MESSAGE);
});

test('oversized payloads, malformed headers and invalid UTF-8 are rejected', async () => {
  const harness = await connectedHarness();
  assert.equal(await harness.radio.send(ADDRESS, 'a'.repeat(16385)), false);
  assert.equal(await harness.radio.send(ADDRESS, ''), false);
  assert.equal(harness.state.writes.length, 0);
  const oversizedHeader = new Uint8Array(8);
  const oversizedView = new DataView(oversizedHeader.buffer);
  oversizedView.setUint32(0, 0x534D0100);
  oversizedView.setUint32(4, 16385);
  harness.receive(oversizedHeader);
  const badMagic = new Uint8Array(9);
  new DataView(badMagic.buffer).setUint32(4, 1);
  harness.receive(badMagic);
  const invalidUtf8 = new Uint8Array(9);
  const utf8View = new DataView(invalidUtf8.buffer);
  utf8View.setUint32(0, 0x534D0100);
  utf8View.setUint32(4, 1);
  invalidUtf8[8] = 0xFF;
  harness.receive(invalidUtf8);
  harness.receive(new Uint8Array(32785));
  assert.equal(harness.state.messages.length, 0);
  assert.equal(harness.state.errors.length, 6);
});

test('stop releases listeners, clears channel count and rejects further writes', async () => {
  const harness = await connectedHarness();
  assert.equal(harness.radio.connectedCount(), 1);
  await harness.radio.stop();
  assert.equal(harness.radio.connectedCount(), 0);
  assert.equal(harness.state.listeners.size, 0);
  assert.equal(await harness.radio.send(ADDRESS, MESSAGE), false);
  assert.equal(harness.state.writes.length, 0);
  assert.equal(harness.state.statuses.at(-1).state, 'stopped');
});

test('stopping during a permission request prevents port creation and advertising after consent arrives', async () => {
  const { radio, state } = makeHarness();
  let release; state.permissionGate = new Promise(resolve => { release = resolve; });
  const starting = radio.start({}); await nextTurn();
  assert.equal(state.permissionRequests, 1);
  await radio.stop(); release();
  assert.equal(await starting, false);
  assert.equal(state.portsCreated, 0); assert.equal(state.advertisements, 0);
  assert.equal(state.listeners.size, 0);
  assert.equal(state.statuses.at(-1).state, 'stopped');
});

test('concurrent starts share one request and a late advertisement is stopped after cancellation', async () => {
  const { radio, state } = makeHarness();
  let release; state.advertisingGate = new Promise(resolve => { release = resolve; });
  const one = radio.start({}), two = radio.start({}); await nextTurn();
  assert.equal(state.permissionRequests, 1); assert.equal(state.portsCreated, 1);
  assert.equal(state.advertisements, 1);
  await radio.stop(); release();
  assert.deepEqual(await Promise.all([one, two]), [false, false]);
  assert.deepEqual(state.stoppedAdvertisements, [7]);
  assert.equal(state.listeners.size, 0);
  state.advertisingGate = undefined;
  assert.equal(await radio.start({}), true, 'a later explicit start can recover');
  await radio.stop();
});

test('confirmed connections clear deadlines and a late connect cannot survive stop', async () => {
  const harness = await connectedHarness();
  assert.equal(harness.state.deferredTimers.filter(Boolean).length, 0);
  await harness.radio.stop();
  const { radio, state, discoverPeer } = makeHarness();
  await radio.start({}); discoverPeer();
  let release; state.connectGate = new Promise(resolve => { release = resolve; });
  const connecting = radio.connect(ADDRESS); await nextTurn();
  await radio.stop(); release();
  assert.equal(await connecting, false);
  assert.ok(state.disconnects.includes(ADDRESS));
  assert.equal(state.deferredTimers.filter(Boolean).length, 0);
  assert.equal(radio.connectedCount(), 0);
});

test('stop interrupts a multi-chunk send without claiming a completed local write', async () => {
  const { radio, state } = await connectedHarness();
  let release; state.writeGate = new Promise(resolve => { release = resolve; });
  const sending = radio.send(ADDRESS, MESSAGE); await nextTurn();
  assert.equal(state.writes.length, 1);
  await radio.stop(); release();
  assert.equal(await sending, false);
  assert.equal(state.writes.length, 1);
});

test('intermediate connection states retain the pending request until confirmation or timeout', async () => {
  const { radio, state, discoverPeer, confirmConnection } = makeHarness();
  await radio.start({}); discoverPeer(); await radio.connect(ADDRESS);
  state.listeners.get('connectionStateChanged')({ address: ADDRESS, uuid: UUID, mtu: 0, state: 0 });
  assert.equal(await radio.connect(ADDRESS), false, 'connecting state must not permit a duplicate request');
  assert.equal(state.deferredTimers.filter(Boolean).length, 1);
  assert.equal(radio.connectedCount(), 0);
  confirmConnection();
  assert.equal(state.deferredTimers.filter(Boolean).length, 0);
  assert.equal(radio.connectedCount(), 1);
  await radio.stop();
});

test('API 20-22 phones rely on the NearLink syscap because isNearLinkSupported() starts at API 23', async () => {
  const { radio, state } = makeHarness({ apiVersion: 22 });
  const status = await radio.probe();
  assert.equal(status.supported, true);
  assert.equal(status.state, 'available');
  assert.equal(state.errors.length, 0, 'the API 23 capability query must not be called on API 22');
  assert.equal(await radio.start({}), true);
  assert.equal(state.advertisements, 1);
});

test('from API 23 the platform capability query decides support', async () => {
  const { radio, state } = makeHarness({ apiVersion: 23, hardware: false });
  const status = await radio.probe();
  assert.equal(status.supported, false);
  assert.equal(status.state, 'unsupported');
  assert.equal(await radio.start({}), false);
  assert.equal(state.advertisements, 0);
});
