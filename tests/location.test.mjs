import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const source = readFileSync(new URL('../entry/src/main/ets/model/DeviceLocation.ets', import.meta.url), 'utf8')
  .replace(/import[^;]+;\s*/g, '');
const javascript = stripTypeScriptTypes(source, { mode: 'strip' }).replace(/export /g, '');

function harness({ supported = true, enabled = true, permissions = [0, 0], location, error } = {}) {
  const calls = [];
  const geo = {
    LocationRequestPriority: { ACCURACY: 1 },
    isLocationEnabled: () => enabled,
    getCurrentLocation: async request => {
      calls.push(['locate', request]);
      if (error) { throw error; }
      return location ?? { latitude: 50.0614, longitude: 19.9372, accuracy: 15 };
    }
  };
  const access = { createAtManager: () => ({ requestPermissionsFromUser: async (_, requested) => {
    calls.push(['permission', requested]);
    return { authResults: permissions };
  } }) };
  const DeviceLocation = new Function('abilityAccessCtrl', 'geoLocationManager', 'canIUse',
    javascript + '\nreturn DeviceLocation;')(access, geo, () => supported);
  return { provider: new DeviceLocation(), calls };
}

test('foreground location requests permissions only when supported and respects denial or disabled services', async () => {
  const unavailable = harness({ supported: false });
  assert.equal((await unavailable.provider.locate({})).status, 'unavailable');
  assert.equal(unavailable.calls.length, 0);
  for (const options of [{ permissions: [-1, -1] }, { permissions: [] }, { enabled: false }]) {
    const app = harness(options);
    assert.notEqual((await app.provider.locate({})).status, 'ready');
    assert.equal(app.calls.filter(call => call[0] === 'locate').length, 0);
  }
});

test('one-shot location uses a bounded request, permits approximate-only consent and returns provider accuracy', async () => {
  const app = harness({ permissions: [0, -1] });
  const result = await app.provider.locate({});
  assert.deepEqual(result, { status: 'ready', latitude: 50.0614, longitude: 19.9372, accuracy: 15 });
  assert.deepEqual(app.calls[0][1], ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
  assert.equal(app.calls[1][1].timeoutMs, 10000);
  assert.equal(app.calls.length, 2);
});

test('invalid locations and provider failures never become successful fixes', async () => {
  for (const location of [
    { latitude: NaN, longitude: 19, accuracy: 10 },
    { latitude: 91, longitude: 19, accuracy: 10 },
    { latitude: 50, longitude: 181, accuracy: 10 },
    { latitude: 50, longitude: 19, accuracy: 0 },
    { latitude: 50, longitude: 19, accuracy: Infinity }
  ]) {
    assert.equal((await harness({ location }).provider.locate({})).status, 'unavailable');
  }
  for (const [code, expected] of [[201, 'permission_denied'], [3301100, 'disabled'], [3301200, 'unavailable']]) {
    assert.equal((await harness({ error: { code } }).provider.locate({})).status, expected);
  }
});
