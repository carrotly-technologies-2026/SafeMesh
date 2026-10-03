import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// One codebase builds two products: HarmonyOS (NearLink Kit) and OpenHarmony/Oniro (stub).
// These checks keep the Oniro variant from regressing the HarmonyOS product and vice versa.
const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('..', import.meta.url));
const studioRoots = [process.env.DEVECO_CLI_STUDIO_PATH, path.join(os.homedir(), 'DevEcoStudio')].filter(Boolean);
const compilerPath = studioRoots
  .map(studio => path.join(studio, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'))
  .find(candidate => fs.existsSync(candidate));
if (!compilerPath) throw new Error('DevEco SDK TypeScript compiler not found. Set DEVECO_CLI_STUDIO_PATH.');
const ts = require(compilerPath);
// Normalize to this realm so deepStrictEqual compares plain values.
const json5 = text => JSON.parse(JSON.stringify(vm.runInNewContext(`(${text})`)));
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');

function loadClass(relative, dependencies) {
  const module = { exports: {} };
  const output = ts.transpileModule(read(relative), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: 'variant.ts'
  }).outputText;
  vm.runInThisContext(`(function(require,module,exports){${output}\n})`)(
    name => { if (name in dependencies) return dependencies[name]; throw new Error(`Unexpected dependency ${name}`); },
    module, module.exports);
  return module.exports.NearLinkTransport;
}

function methods(Class) {
  return Object.getOwnPropertyNames(Class.prototype).filter(name => name !== 'constructor' && !name.startsWith('on'));
}

function etsFiles(directory) {
  return fs.readdirSync(path.join(root, directory), { recursive: true })
    .filter(name => String(name).endsWith('.ets')).map(name => path.join(directory, String(name)));
}

const OniroTransport = loadClass('entry/src/oniro/transport/NearLinkTransport.ets', { '@kit.AbilityKit': {} });

test('the Oniro stub reports NearLink as unsupported and never claims a link or delivery', async () => {
  const statuses = [];
  const transport = new OniroTransport({ onStatus: status => statuses.push(status), onPeer() {}, onMessage() {}, onError() {} });
  const probed = await transport.probe();
  assert.equal(probed.state, 'unsupported');
  assert.equal(probed.supported, false);
  assert.equal(await transport.start({}), false);
  assert.equal(await transport.discover('SM-B'), false);
  assert.equal(await transport.connect('B'), false);
  assert.equal(await transport.send('B', '{}'), false);
  assert.equal(await transport.broadcast('{}'), 0);
  assert.equal(transport.isSupported(), false);
  assert.equal(transport.connectedCount(), 0);
  await transport.stop();
  assert.ok(statuses.length >= 2 && statuses.every(status => status.state === 'unsupported'));
});

test('both NearLink variants expose the same public API to the relay', () => {
  const HarmonyTransport = loadClass('entry/src/harmonyos/transport/NearLinkTransport.ets', {
    '@kit.AbilityKit': {}, '@kit.ArkTS': { util: { TextEncoder: class {}, TextDecoder: { create() { return {}; } } } },
    '@kit.BasicServicesKit': {}, '@kit.NearLinkKit': {}
  });
  const publicApi = ['broadcast', 'connect', 'connectedCount', 'discover', 'isSupported', 'probe', 'send', 'start', 'stop'];
  assert.deepEqual(methods(OniroTransport).sort(), publicApi);
  for (const name of publicApi) {
    assert.equal(typeof HarmonyTransport.prototype[name], 'function', `HarmonyOS adapter lacks ${name}`);
  }
});

test('NearLink Kit stays in the HarmonyOS source root and the relay resolves the adapter per target', () => {
  for (const file of [...etsFiles('entry/src/main'), ...etsFiles('entry/src/oniro')]) {
    assert.doesNotMatch(read(file), /@kit\.NearLinkKit/, `${file} must not import NearLink Kit`);
  }
  assert.match(read('entry/src/harmonyos/transport/NearLinkTransport.ets'), /import lazy \{[^}]+\} from '@kit\.NearLinkKit'/);
  assert.match(read('entry/src/main/ets/viewmodel/RelayViewModel.ets'), /from 'entry\/transport\/NearLinkTransport'/);
  assert.equal(fs.existsSync(path.join(root, 'entry/src/main/ets/transport/NearLinkTransport.ets')), false,
    'a src/main copy would shadow neither variant and break the target split');
});

test('build profiles keep the HarmonyOS product unchanged and add an Oniro product', () => {
  const project = json5(read('build-profile.json5'));
  const products = Object.fromEntries(project.app.products.map(product => [product.name, product]));
  assert.equal(products.default.runtimeOS, 'HarmonyOS');
  assert.equal(products.default.targetSdkVersion, '6.1.1(24)');
  assert.equal(products.default.compatibleSdkVersion, '6.0.0(20)');
  assert.equal(products.oniro.runtimeOS, 'OpenHarmony');
  assert.equal(products.oniro.compatibleSdkVersion, 20);
  assert.deepEqual(project.app.signingConfigs.map(config => config.name), ['oniro'],
    'the HarmonyOS product must stay unsigned in Git; phones are signed locally');
  const targets = Object.fromEntries(project.modules[0].targets.map(target => [target.name, target.applyToProducts]));
  assert.deepEqual(targets, { default: ['default'], oniro: ['oniro'] });
  const entry = json5(read('entry/build-profile.json5'));
  const roots = Object.fromEntries(entry.targets.filter(target => target.source).map(target => [target.name, target.source.sourceRoots]));
  assert.deepEqual(roots, { default: ['./src/harmonyos'], oniro: ['./src/oniro'] });
  const manifest = json5(read('entry/src/main/module.json5')).module;
  assert.deepEqual(manifest.deviceTypes, ['phone']);
  assert.ok(manifest.requestPermissions.some(permission => permission.name === 'ohos.permission.ACCESS_NEARLINK'));
  const hvigorfile = read('hvigorfile.ts');
  assert.match(hvigorfile, /ONIRO_PRODUCT = 'oniro'/);
  assert.match(hvigorfile, /deviceTypes = \['default'\]/);
  assert.match(hvigorfile, /ohos\.permission\.ACCESS_NEARLINK/);
});
