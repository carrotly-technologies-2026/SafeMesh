import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// Runs the actual AlertFeedback source; only the platform vibrator is mocked.
const require = createRequire(import.meta.url);
const studioRoots = [process.env.DEVECO_CLI_STUDIO_PATH, path.join(os.homedir(), 'DevEcoStudio')].filter(Boolean);
const compilerPath = studioRoots
  .map(studio => path.join(studio, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'))
  .find(candidate => fs.existsSync(candidate));
if (!compilerPath) throw new Error('DevEco SDK TypeScript compiler not found. Set DEVECO_CLI_STUDIO_PATH.');
const ts = require(compilerPath);
const sourcePath = fileURLToPath(new URL('../entry/src/main/ets/model/AlertFeedback.ets', import.meta.url));
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: 'AlertFeedback.ts'
}).outputText;

function load({ presetSupported = true, fails = false } = {}) {
  const calls = [];
  const vibrator = {
    async isSupportEffect(effectId) { calls.push({ query: effectId }); return presetSupported; },
    async startVibration(effect, attribute) {
      calls.push({ effect, attribute });
      if (fails) throw Object.assign(new Error('Capability not supported.'), { code: 801 });
    }
  };
  const module = { exports: {} };
  vm.runInNewContext(compiled, {
    module, exports: module.exports, console: { info() {}, warn() {} },
    require(name) { if (name === '@kit.SensorServiceKit') return { vibrator }; throw new Error(`Unexpected ${name}`); }
  });
  return { feedback: new module.exports.AlertFeedback(), calls };
}

test('a supported preset vibrates once for warnings and three times for critical alerts', async () => {
  const { feedback, calls } = load();
  assert.equal(await feedback.vibrate('warning'), true);
  assert.equal(await feedback.vibrate('critical'), true);
  const starts = calls.filter(call => call.effect);
  assert.deepEqual(JSON.parse(JSON.stringify(starts.map(call => [call.effect, call.attribute]))), [
    [{ type: 'preset', effectId: 'haptic.notice.warning', count: 1 }, { usage: 'notification' }],
    [{ type: 'preset', effectId: 'haptic.notice.warning', count: 3 }, { usage: 'alarm' }]
  ]);
});

test('without the preset a short timed vibration is used, longer for critical alerts', async () => {
  const { feedback, calls } = load({ presetSupported: false });
  await feedback.vibrate('info');
  await feedback.vibrate('critical');
  const durations = calls.filter(call => call.effect).map(call => [call.effect.type, call.effect.duration, call.attribute.usage]);
  assert.deepEqual(durations, [['time', 300, 'notification'], ['time', 900, 'alarm']]);
});

test('a missing vibrator or denied permission never throws into the alert flow', async () => {
  const { feedback } = load({ fails: true });
  assert.equal(await feedback.vibrate('critical'), false);
});
