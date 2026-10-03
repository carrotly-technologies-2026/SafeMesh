import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
let ts;
try { ts = require('typescript'); } catch {
  const studio = process.env.DEVECO_CLI_STUDIO_PATH || join(process.env.USERPROFILE || '', 'DevEcoStudio');
  const compiler = process.env.ARKTS_TYPESCRIPT_PATH || join(studio,
    'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
  if (!existsSync(compiler)) throw new Error('Set ARKTS_TYPESCRIPT_PATH or install TypeScript for host tests.');
  ts = require(compiler);
}

class FakePreferences {
  constructor(durable = new Map()) {
    this.disk = new Map(durable);
    this.memory = new Map(durable);
    this.flushCount = 0;
    this.putCount = 0;
    this.failFlushAt = -1;
    this.failPutAt = -1;
    this.throwAfterCommit = false;
    this.observer = undefined;
  }
  async get(key, fallback) { return this.memory.has(key) ? this.memory.get(key) : fallback; }
  async put(key, value) {
    this.putCount++;
    if (this.putCount === this.failPutAt) throw new Error('simulated put failure');
    assert.ok(key.length <= 80, 'native preference key bound');
    assert.equal(typeof value, 'string');
    assert.ok(value.length <= 8192, 'native preference string bound');
    assert.ok(Buffer.byteLength(value, 'utf8') <= 8192, 'conservative UTF-8 bound');
    // Model a UTF-8 boundary to expose accidentally split surrogate pairs.
    this.memory.set(key, Buffer.from(value).toString('utf8'));
  }
  async flush() {
    this.flushCount++;
    if (this.observer) this.observer(this);
    if (this.flushCount === this.failFlushAt) {
      if (this.throwAfterCommit) this.disk = new Map(this.memory);
      throw new Error('simulated flush failure');
    }
    this.disk = new Map(this.memory);
  }
}

function implementation(provider) {
  const filename = resolve(root, 'entry/src/main/ets/model/LocalStore.ets');
  const output = ts.transpileModule(readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: 'LocalStore.ts'
  }).outputText;
  const module = { exports: {} };
  vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename })(specifier => {
    if (specifier === '@kit.ArkData') return { preferences: { getPreferences: provider } };
    throw new Error(`Unexpected storage dependency: ${specifier}`);
  }, module, module.exports);
  return module.exports.LocalStore;
}
async function opened(native = new FakePreferences()) {
  const LocalStore = implementation(async () => native);
  const store = new LocalStore();
  await store.init({});
  return { store, native };
}

test('actual LocalStore round-trips a maximum-size snapshot and respects every native string bound', async () => {
  const { store, native } = await opened();
  const value = ('A'.repeat(2047) + '🛟').repeat(520).slice(0, 128 * 8192 - 1) + 'Z';
  assert.equal(value.length, 128 * 8192);
  await store.write('relay_cache_v1', value);
  assert.equal(await store.read('relay_cache_v1'), value);
  const restored = await opened(new FakePreferences(native.disk));
  assert.equal(await restored.store.read('relay_cache_v1'), value);
});

test('the prior generation remains the head until all replacement chunks have flushed', async () => {
  const { store, native } = await opened();
  await store.write('relay_cache_v1', 'original');
  const headKey = 'sm2:relay_cache_v1:head';
  const oldHead = native.disk.get(headKey);
  const stagingFlush = native.flushCount + 1;
  native.observer = current => {
    if (current.flushCount === stagingFlush) {
      assert.equal(current.memory.get(headKey), oldHead);
      assert.equal(current.disk.get(headKey), oldHead);
    }
  };
  await store.write('relay_cache_v1', 'replacement'.repeat(5000));
  assert.equal(await store.read('relay_cache_v1'), 'replacement'.repeat(5000));
  assert.equal(native.memory.get('sm2:relay_cache_v1:a:0'), 'original');
});

test('failed staging put or flush preserves a complete prior generation after restart', async () => {
  for (const phase of ['put', 'flush']) {
    const { store, native } = await opened();
    await store.write('relay_cache_v1', 'original');
    if (phase === 'put') native.failPutAt = native.putCount + 2;
    else native.failFlushAt = native.flushCount + 1;
    await assert.rejects(() => store.write('relay_cache_v1', 'replacement'.repeat(1000)));
    assert.equal(await store.read('relay_cache_v1'), 'original');
    const restored = await opened(new FakePreferences(native.disk));
    assert.equal(await restored.store.read('relay_cache_v1'), 'original');
  }
});

test('failed head publication rolls back memory; any durable generation is complete', async () => {
  for (const mayHaveCommitted of [false, true]) {
    const { store, native } = await opened();
    await store.write('relay_cache_v1', 'original');
    native.failFlushAt = native.flushCount + 2;
    native.throwAfterCommit = mayHaveCommitted;
    const replacement = 'replacement'.repeat(1000);
    await assert.rejects(() => store.write('relay_cache_v1', replacement));
    assert.equal(await store.read('relay_cache_v1'), 'original');
    const restored = await opened(new FakePreferences(native.disk));
    assert.equal(await restored.store.read('relay_cache_v1'), mayHaveCommitted ? replacement : 'original');
  }
});

test('uninitialized operations reject and operations during initialization await readiness', async () => {
  let release;
  const native = new FakePreferences();
  const gate = new Promise(resolve => { release = resolve; });
  const LocalStore = implementation(async () => { await gate; return native; });
  const missing = new LocalStore();
  await assert.rejects(() => missing.write('saved_point', 'p1'), /init/);
  await assert.rejects(() => missing.read('saved_point'), /init/);
  const store = new LocalStore();
  const initialization = store.init({});
  const write = store.write('saved_point', 'p1');
  assert.equal(native.putCount, 0);
  release();
  await Promise.all([initialization, write]);
  assert.equal(await store.read('saved_point'), 'p1');
});

test('serialized concurrent reads and writes cannot mix generations', async () => {
  const { store } = await opened();
  const first = 'A'.repeat(22000), second = 'B'.repeat(26000);
  const results = await Promise.all([
    store.write('relay_cache_v1', first), store.read('relay_cache_v1'),
    store.write('relay_cache_v1', second), store.read('relay_cache_v1')
  ]);
  assert.equal(results[1], first);
  assert.equal(results[3], second);
});

test('legacy values and empty values work; corrupt or oversized values fail closed', async () => {
  const { store, native } = await opened(new FakePreferences(new Map([['saved_point', 'legacy-p1']])));
  assert.equal(await store.read('saved_point'), 'legacy-p1');
  await store.write('saved_point', '');
  assert.equal(await store.read('saved_point'), '');
  await assert.rejects(() => store.write('relay_cache_v1', 'X'.repeat(128 * 8192 + 1)), /capacity/);
  await assert.rejects(() => store.write('../invalid', 'value'), /key/);
  await store.write('relay_cache_v1', 'A'.repeat(5000));
  native.memory.delete('sm2:relay_cache_v1:a:1');
  await assert.rejects(() => store.read('relay_cache_v1'), /Incomplete/);
});
