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
const { MapViewModel, MapShape, MapVertex } = new Function(...dataNames,
  eraseTypes(modelSource) + '\nreturn { MapViewModel, MapShape, MapVertex };')(...dataNames.map(name => data[name]));

class CanvasMock {
  calls = { stroke: 0, lineTo: 0, moveTo: 0, fill: 0, fillRect: 0, clip: 0 };
  beginPath() {}
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
  fill() { this.calls.fill++; }
  stroke() { this.calls.stroke++; }
  fillText() {}
  arc() {}
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
  model.select('unknown-id');
  assert.equal(JSON.stringify(model), before);
  model.select('');
  assert.equal(JSON.stringify(model), before);
});

test('valid selection centers an existing source point; recenter retains origin and sensible zoom', () => {
  const model = new MapViewModel();
  const point = model.points[10];
  model.select(point.id);
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
