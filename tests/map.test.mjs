import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

// These tests execute the actual checked-in ArkTS methods after type erasure.
// ArkUI decorators/build() are removed and only the native Canvas is mocked.
// This checks data/geometry behavior, not native ArkUI lifecycle or pixel output.
// Data: © OpenStreetMap contributors, ODbL https://www.openstreetmap.org/copyright
// Protective points: Komenda Główna PSP, CC BY 4.0; provenance and limitations:
// ../artifacts/research/maps.md and the bundled map-pack.json metadata.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = relative => readFileSync(resolve(root, relative), 'utf8');
const eraseTypes = source => stripTypeScriptTypes(source, { mode: 'strip' }).replace(/export /g, '');
const dataNames = ['MAP_AREAS', 'MAP_STREETS', 'MAP_RIVERS', 'SAFE_POINTS',
  'MAP_SOURCE_DATE', 'MAP_ATTRIBUTION', 'MAP_PACK_BYTES', 'MAP_BOUNDS'];
const data = new Function(eraseTypes(read('entry/src/main/ets/model/OfflineMapData.ets')) +
  `\nreturn {${dataNames.join(',')}};`)();
const pack = JSON.parse(read('entry/src/main/resources/rawfile/map-pack.json'));
const modelSource = read('entry/src/main/ets/viewmodel/MapViewModel.ets')
  .replace(/import[\s\S]*?;\s*/g, '').replace('@Observed', '');
class LocationMock {
  static next = Promise.resolve({ status: 'unavailable' });
  locate() { return LocationMock.next; }
}
const { MapViewModel, MapShape, MapVertex } = new Function(...dataNames, 'DeviceLocation',
  eraseTypes(modelSource) + '\nreturn { MapViewModel, MapShape, MapVertex };')(...dataNames.map(name => data[name]), LocationMock);

class CanvasMock {
  calls = { stroke: 0, lineTo: 0, moveTo: 0, fill: 0, fillRect: 0, clip: 0 };
  globalAlpha = 1;
  currentArc;
  markerFills = [];
  colors = [];
  beginPath() { this.currentArc = undefined; }
  closePath() {}
  moveTo(x, y) { assert(Number.isFinite(x) && Number.isFinite(y)); this.calls.moveTo++; }
  lineTo(x, y) { assert(Number.isFinite(x) && Number.isFinite(y)); this.calls.lineTo++; }
  fillRect() { this.calls.fillRect++; }
  strokeRect() {}
  rect(x, y, width, height) {
    assert([x, y, width, height].every(Number.isFinite));
    assert(width > 0 && height > 0);
  }
  clip() { this.calls.clip++; }
  save() {}
  restore() {}
  fill() {
    this.calls.fill++; this.colors.push(this.fillStyle);
    if (this.currentArc) this.markerFills.push({ ...this.currentArc, color: this.fillStyle, alpha: this.globalAlpha });
  }
  stroke() { this.calls.stroke++; }
  fillText() {}
  measureText(text) { return { width: text.length * 6.5 }; }
  arc(x, y, radius) { this.currentArc = { x, y, radius }; }
}
class SettingsMock {}
let viewSource = read('entry/src/main/ets/views/OfflineMap.ets').replace(/import[\s\S]*?;\s*/g, '');
assert(viewSource.includes('  build() {'), 'The host adapter must identify the ArkUI build method explicitly');
viewSource = viewSource.slice(0, viewSource.indexOf('  build() {')) + '\n}';
viewSource = viewSource.replace('@Component', '').replace('export struct OfflineMap', 'class OfflineMap')
  .replace(/@ObjectLink |@Prop |@Watch\('onRevisionChanged'\) /g, '');
const OfflineMap = new Function('CanvasRenderingContext2D', 'RenderingContextSettings', 'MAP_BOUNDS',
  eraseTypes(viewSource) + '\nreturn OfflineMap;')(CanvasMock, SettingsMock, data.MAP_BOUNDS);
const createView = () => {
  const view = new OfflineMap();
  view.vm = new MapViewModel();
  return view;
};

test('compiled reference data preserves JSON source records, licensing and finite pack bounds', () => {
  const bounds = data.MAP_BOUNDS;
  assert(Object.values(bounds).every(Number.isFinite));
  assert(bounds.south < bounds.north && bounds.west < bounds.east);
  assert.equal(data.MAP_SOURCE_DATE, pack.metadata.pspDataDate);
  assert.equal(data.MAP_PACK_BYTES, Buffer.byteLength(read('entry/src/main/resources/rawfile/map-pack.json')));
  assert.match(data.MAP_ATTRIBUTION, /OpenStreetMap contributors/);
  assert.match(data.MAP_ATTRIBUTION, /ODbL/);
  assert.match(data.MAP_ATTRIBUTION, /PSP.*CC BY 4\.0/);
  assert.equal(pack.metadata.pspLicense, 'CC BY 4.0');
  assert.equal(pack.metadata.osmLicense, 'ODbL 1.0');
  assert(data.SAFE_POINTS.length >= 20 && data.SAFE_POINTS.length <= 50);
  assert.equal(new Set(data.SAFE_POINTS.map(point => point.id)).size, data.SAFE_POINTS.length);
  const sources = new Map(pack.safePoints.map(point => [point.id, point]));
  for (const point of data.SAFE_POINTS) {
    assert.deepEqual({ ...point }, sources.get(point.id));
    assert(Number.isFinite(point.lat) && Number.isFinite(point.lon));
    assert(point.lat >= bounds.south && point.lat <= bounds.north);
    assert(point.lon >= bounds.west && point.lon <= bounds.east);
    assert.match(point.id, /^OZO-/);
  }
});

test('all source geometry and cached shape bounds are finite, complete and consistent', () => {
  const model = new MapViewModel();
  for (const [source, shapes] of [[data.MAP_STREETS, model.streets],
    [data.MAP_AREAS, model.areas], [data.MAP_RIVERS, model.rivers]]) {
    assert.equal(source.length, shapes.length);
    assert.equal(new Set(source.map(shape => shape.id)).size, source.length);
    for (let index = 0; index < shapes.length; index++) {
      const shape = shapes[index];
      assert(shape.points.length >= 2);
      assert.equal(shape.points.length, source[index].points.length);
      assert([shape.minLat, shape.maxLat, shape.minLon, shape.maxLon].every(Number.isFinite));
      assert(shape.minLat <= shape.maxLat && shape.minLon <= shape.maxLon);
      for (const point of shape.points) {
        assert(Number.isFinite(point.lat) && Number.isFinite(point.lon));
        assert(point.lat >= -90 && point.lat <= 90 && point.lon >= -180 && point.lon <= 180);
        assert(point.lat >= shape.minLat && point.lat <= shape.maxLat);
        assert(point.lon >= shape.minLon && point.lon <= shape.maxLon);
      }
    }
  }
  for (const area of model.areas) {
    assert(area.points.length >= 4);
    assert.deepEqual(area.points[0], area.points.at(-1));
  }
});

test('straight-line distance uses metres, stays finite at antipodes and orders real points', () => {
  const model = new MapViewModel();
  assert.equal(model.distance(model.originLat, model.originLon), 0);
  // Independent reference: one degree of meridian on a 6,371 km sphere.
  assert(Math.abs(model.distance(model.originLat + 1, model.originLon) - 111194.92664455874) < 0.001);
  const antipodal = model.distance(-model.originLat, model.originLon - 180);
  assert(Number.isFinite(antipodal));
  assert(Math.abs(antipodal - 20015086.79602057) < 1);
  assert(model.points.every((point, index, points) => Number.isFinite(point.distance) &&
    point.distance >= 0 && (index === 0 || point.distance >= points[index - 1].distance)));
  assert.equal(model.selected().id, model.points[0].id);
});

test('unknown selected IDs cannot mutate any model state or move the map to 0,0', () => {
  const model = new MapViewModel();
  model.select(model.points[10].id);
  model.savedId = model.points[3].id;
  model.changeZoom(2);
  const before = JSON.stringify(model);
  assert.equal(model.select('unknown-id'), false);
  assert.equal(JSON.stringify(model), before);
  assert.equal(model.select(''), false);
  assert.equal(JSON.stringify(model), before);
});

test('valid selection centers an existing source point; recenter retains origin and sensible zoom', () => {
  const model = new MapViewModel();
  const point = model.points[10];
  assert.equal(model.select(point.id), true);
  assert.equal(model.selected(), point);
  assert.equal(model.centerLat, point.lat);
  assert.equal(model.centerLon, point.lon);
  model.changeZoom(100);
  assert(model.zoom > 0 && model.zoom <= 5);
  model.changeZoom(-100);
  assert(model.zoom >= 0.65);
  model.recenter();
  assert.equal(model.centerLat, model.originLat);
  assert.equal(model.centerLon, model.originLon);
  assert.equal(model.zoom, 1);
});

test('native map coordinate methods align east/north and use near-isotropic local distance', () => {
  const view = createView();
  assert.equal(view.x(view.vm.centerLon), view.widthValue / 2);
  assert.equal(view.y(view.vm.centerLat), view.heightValue / 2);
  const north100m = view.vm.centerLat + 100 / 111195;
  const east100m = view.vm.centerLon + 100 / (111195 * Math.cos(view.vm.centerLat * Math.PI / 180));
  const northPixels = view.heightValue / 2 - view.y(north100m);
  const eastPixels = view.x(east100m) - view.widthValue / 2;
  assert(northPixels > 0 && eastPixels > 0);
  assert(Math.abs(eastPixels / northPixels - 1) < 0.001);
  const farAway = new MapShape('residential', [new MapVertex(51, 20), new MapVertex(51.1, 20.1)]);
  assert.equal(view.visible(farAway), false);
});

test('map waits for native readiness and batches actual geometry within a small stroke budget', () => {
  const view = createView();
  view.draw();
  assert.equal(view.canvas.calls.fillRect, 0);
  view.canvasReady = true;
  view.draw();
  assert(view.canvas.calls.stroke < 80, 'Road drawing should not submit thousands of separate strokes');
  assert(view.canvas.calls.lineTo > 1000, 'Real OSM geometry must still reach Canvas');
  assert.equal(view.canvas.calls.clip, 1, 'Intersecting OSM ways must be clipped to the downloaded extent');
  const allSegments = view.vm.streets.reduce((sum, shape) => sum + shape.points.length - 1, 0);
  assert(view.canvas.calls.lineTo < allSegments, 'Default viewport should cull geometry outside its bounds');
});

test('marker picking reports a visible source ID and leaves empty locations unselected', () => {
  const view = createView();
  let picked = '';
  view.onSelect = id => { picked = id; };
  const point = view.vm.points[5];
  view.pick(view.x(point.lon), view.y(point.lat));
  assert(data.SAFE_POINTS.some(source => source.id === picked));
  picked = '';
  view.pick(-1000, -1000);
  assert.equal(picked, '');
});

test('save badge changes only after durable success, keeps the original requested point during selection changes', async () => {
  const model = new MapViewModel();
  const previousId = model.points[3].id;
  model.savedId = previousId;
  const requestedId = model.selectedId;
  let finish;
  const pending = new Promise(resolve => { finish = resolve; });
  const calls = [];
  const saving = model.saveSelected({ write: async (key, value) => { calls.push([key, value]); await pending; } });
  assert.equal(model.saveBusy, true);
  assert.equal(model.savedId, previousId);
  assert.equal(await model.saveSelected({ write: async () => assert.fail('Double save must not write') }), false);
  model.select(model.points[5].id);
  finish();
  assert.equal(await saving, true);
  assert.deepEqual(calls, [['saved_point', requestedId]]);
  assert.equal(model.savedId, requestedId);
  assert.equal(model.saveBusy, false);
  const result = await model.saveSelected({ write: async () => { throw new Error('disk full'); } });
  assert.equal(result, false);
  assert.equal(model.savedId, requestedId);
  assert.equal(model.saveError, 'save_failed');
  assert.equal(model.saveBusy, false);
  assert.equal(model.openSaved(), true);
  assert.equal(model.selectedId, requestedId);
});

test('saved-point restore ignores unknown IDs, handles errors and cannot overwrite a concurrent newer save', async () => {
  const model = new MapViewModel();
  await model.restoreSaved({ read: async () => 'untrusted-unknown-point' });
  assert.equal(model.savedId, '');
  assert.equal(model.openSaved(), false);
  await model.restoreSaved({ read: async () => { throw new Error('unreadable'); } });
  assert.equal(model.saveError, 'load_failed');
  let finish;
  const previousId = model.points[4].id;
  const restoring = model.restoreSaved({ read: () => new Promise(resolve => { finish = resolve; }) });
  assert.equal(await model.saveSelected({ write: async () => {} }), true);
  const savedId = model.savedId;
  finish(previousId);
  await restoring;
  assert.equal(model.savedId, savedId);
  model.selectedId = 'not-a-point';
  assert.equal(await model.saveSelected({ write: async () => assert.fail('Unknown point must not persist') }), false);
  assert.equal(model.saveError, 'invalid_point');
});

test('device origin only accepts a usable fix in the downloaded area and reorders real distances', async () => {
  const model = new MapViewModel();
  const original = [model.originLat, model.originLon];
  for (const position of [
    { status: 'permission_denied' },
    { status: 'disabled' },
    { status: 'ready', latitude: 50.061, longitude: 19.936, accuracy: 3000 },
    { status: 'ready', latitude: 52.23, longitude: 21.01, accuracy: 10 }
  ]) {
    LocationMock.next = Promise.resolve(position);
    assert.equal(await model.locate({}), false);
    assert.deepEqual([model.originLat, model.originLon], original);
    assert.equal(model.originIsDevice, false);
    assert.equal(model.locationBusy, false);
  }
  assert.equal(model.locationStatus, 'outside_pack');
  const point = model.points[10];
  LocationMock.next = Promise.resolve({ status: 'ready', latitude: point.lat, longitude: point.lon, accuracy: 12 });
  assert.equal(await model.locate({}), true);
  assert.equal(model.originIsDevice, true);
  assert.equal(model.locationAccuracy, 12);
  assert.equal(model.points[0].id, point.id);
  assert.equal(model.points[0].distance, 0);
  assert.equal(model.centerLat, point.lat);
  model.resetOrigin();
  assert.deepEqual([model.originLat, model.originLon], original);
  assert.equal(model.originIsDevice, false);
  assert.equal(model.locationStatus, 'demo');
});

test('a late location response cannot replace a user-selected reset to the demo origin', async () => {
  const model = new MapViewModel();
  let finish;
  LocationMock.next = new Promise(resolve => { finish = resolve; });
  const pending = model.locate({});
  assert.equal(model.locationBusy, true);
  assert.equal(await model.locate({}), false);
  model.resetOrigin();
  finish({ status: 'ready', latitude: 50.065, longitude: 19.940, accuracy: 8 });
  assert.equal(await pending, false);
  assert.equal(model.locationStatus, 'demo');
  assert.equal(model.originIsDevice, false);
  assert.equal(model.locationBusy, false);
});

test('address search accepts an accent-free Polish keyboard, token order and whitespace without changing map selection', () => {
  const model = new MapViewModel();
  const before = JSON.stringify(model);
  assert.equal(model.searchPoints('  ').length, model.points.length);
  assert(model.searchPoints('GLOWNY').some(point => point.address === 'Rynek Główny 1, Kraków'));
  assert.deepEqual(model.searchPoints('  krakow   25 glowny  ').map(point => point.address), ['Rynek Główny 25, Kraków']);
  assert.deepEqual(model.searchPoints('GŁÓWNY').map(point => point.id), model.searchPoints('glowny').map(point => point.id));
  assert.equal(model.searchPoints('nonexistent-street-abcxyz').length, 0);
  assert.equal(JSON.stringify(model), before, 'Filtering must preserve selection, source addresses and distance order');
});

test('access categories expose only stable localization keys and retain point provenance after origin changes', async () => {
  const model = new MapViewModel();
  const knownKeys = new Set(['availability_request', 'availability_all_day', 'availability_hours']);
  assert.deepEqual(new Set(model.points.map(point => point.availabilityKey)), knownKeys);
  const original = new Map(model.points.map(point => [point.id,
    { key: point.availabilityKey, source: point.source, sourceDate: point.sourceDate }]));
  const point = model.points[10];
  LocationMock.next = Promise.resolve({ status: 'ready', latitude: point.lat, longitude: point.lon, accuracy: 12 });
  assert.equal(await model.locate({}), true);
  model.resetOrigin();
  for (const item of model.points) {
    assert.deepEqual({ key: item.availabilityKey, source: item.source, sourceDate: item.sourceDate }, original.get(item.id));
    assert.match(item.source, /Państwowej Straży Pożarnej/);
    assert.equal(item.sourceDate, model.sourceDate);
  }
  const sourcePoint = data.SAFE_POINTS[0];
  const oldCategory = sourcePoint.availability;
  try {
    sourcePoint.availability = 'Unrecognized English access category';
    const unknown = new MapViewModel().points.find(item => item.id === sourcePoint.id);
    assert.equal(unknown.availabilityKey, 'availability_unknown');
  } finally { sourcePoint.availability = oldCategory; }
});

test('distance presentation follows the selected language and guards unavailable values', () => {
  const model = new MapViewModel();
  const point = model.points[0];
  point.distance = 1400;
  assert.equal(model.distanceText(point, 'pl'), '1,4 km');
  assert.equal(model.distanceText(point, 'en'), '1.4 km');
  point.distance = 153.4;
  assert.equal(model.distanceText(point, 'pl'), '153 m');
  assert.equal(model.distanceText(point, 'en'), '153 m');
  for (const invalid of [NaN, Infinity, -1]) {
    point.distance = invalid;
    assert.equal(model.distanceText(point, 'pl'), '—');
  }
});

test('saved-point entry is absent for missing IDs and returns the durable point independently of current selection', () => {
  const model = new MapViewModel();
  assert.equal(model.saved(), undefined);
  model.savedId = 'missing';
  assert.equal(model.saved(), undefined);
  const point = model.points[4];
  model.savedId = point.id;
  model.select(model.points[8].id);
  assert.equal(model.saved(), point);
  assert.equal(model.openSaved(), true);
  assert.equal(model.selected(), point);
});

test('selected marker paints above coincident points and origin, and hit testing agrees with the visible marker', () => {
  const view = createView();
  const selected = view.vm.points[1];
  const underneath = view.vm.points[0];
  // A real map can contain several source points at the same entrance.
  underneath.lat = selected.lat; underneath.lon = selected.lon;
  view.vm.originLat = selected.lat; view.vm.originLon = selected.lon;
  view.vm.select(selected.id);
  view.canvasReady = true;
  view.draw();
  const top = view.canvas.markerFills.at(-1);
  assert.deepEqual(top, { x: view.widthValue / 2, y: view.heightValue / 2,
    radius: 11, color: '#164D40', alpha: 1 });
  assert(view.canvas.markerFills.some(mark => mark.alpha === 0.18));
  assert.equal(view.canvas.globalAlpha, 1, 'Origin transparency must not leak into point markers');
  let chosen;
  view.onSelect = id => { chosen = id; };
  view.pick(view.widthValue / 2, view.heightValue / 2);
  assert.equal(chosen, selected.id);
});

test('theme revision re-reads Canvas resources for the selected marker', () => {
  const view = createView();
  let selectedColor = 0xff164d40;
  view.getUIContext = () => ({ getHostContext: () => ({ resourceManager: {
    getColorByNameSync: name => name === 'map_selected' ? selectedColor : 0xffdddddd
  } }) });
  view.canvasReady = true;
  view.draw();
  assert.equal(view.canvas.markerFills.at(-1).color, '#164d40');
  selectedColor = 0xffd8f58a;
  view.dark = true;
  view.onRevisionChanged();
  assert.equal(view.canvas.markerFills.at(-1).color, '#d8f58a');
});
