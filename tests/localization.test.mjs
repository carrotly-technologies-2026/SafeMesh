import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const resource = language => JSON.parse(readFileSync(join(root,
  'entry/src/main/resources', language, 'element/string.json'), 'utf8'));
const resources = Object.fromEntries(['base', 'en', 'pl'].map(language => [language, resource(language)]));
const strings = Object.fromEntries(Object.entries(resources).map(([language, data]) =>
  [language, new Map(data.string.map(item => [item.name, item.value]))]));
const packets = ['none', 'ack_matched', 'ack_unmatched', 'malformed', 'accepted', 'duplicate', 'invalid',
  'untrusted', 'hop_limit', 'expired', 'future', 'busy', 'capacity', 'processing_failed'];
const checks = ['idle', 'running', 'passed', 'failed', 'error'];
const events = ['a', 'b', 'c', 'duplicate', 'tampered', 'expired', 'error'];
const dynamicKeys = [
  ...packets.map(value => 'packet_' + value),
  ...checks.map(value => 'test_' + value),
  ...events.flatMap(value => ['relay_event_' + value, 'relay_detail_' + value]),
  ...['en', 'pl', 'und'].map(value => 'original_language_' + value),
  ...['request', 'all_day', 'hours', 'unknown'].map(value => 'availability_' + value),
  ...['ready', 'permission_denied', 'disabled', 'unavailable', 'outside_pack', 'poor_accuracy']
    .map(value => 'location_' + value)
];

test('base and English resources agree, all locales have complete unique nonempty UTF-8 keys', () => {
  assert.deepEqual(resources.base, resources.en, 'Base must be the English fallback');
  const expected = [...strings.en.keys()].sort();
  for (const [language, data] of Object.entries(resources)) {
    assert.equal(data.string.length, strings[language].size, `${language}: duplicate key`);
    assert.deepEqual([...strings[language].keys()].sort(), expected, `${language}: missing or extra keys`);
    for (const item of data.string) {
      assert.match(item.name, /^[A-Za-z][A-Za-z0-9_]*$/);
      assert.equal(typeof item.value, 'string');
      assert.ok(item.value.trim().length > 0, `${language}:${item.name}: empty value`);
      assert.doesNotMatch(item.value, /\uFFFD|Ã|Ä…|Ĺ‚|đź/, `${language}:${item.name}: encoding corruption`);
    }
  }
});

test('packet verdicts, test events and map access states have localized labels rather than raw enum values', () => {
  for (const key of dynamicKeys) {
    assert.ok(strings.en.has(key), `English missing ${key}`);
    assert.ok(strings.pl.has(key), `Polish missing ${key}`);
    assert.notEqual(strings.en.get(key), strings.pl.get(key), `${key}: untranslated Polish status`);
    assert.notEqual(strings.pl.get(key), key, `${key}: raw resource key`);
  }
});

function sourceFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(item => {
    const path = join(directory, item.name);
    return item.isDirectory() ? sourceFiles(path) : item.name.endsWith('.ets') ? [path] : [];
  });
}

test('every literal UI string key resolves in all languages', () => {
  for (const path of sourceFiles(join(root, 'entry/src/main/ets'))) {
    const source = readFileSync(path, 'utf8');
    const keys = [...source.matchAll(/\bthis\.(?:t|section)\('([A-Za-z][A-Za-z0-9_]*)'\)/g),
      ...source.matchAll(/\$r\('app\.string\.([A-Za-z][A-Za-z0-9_]*)'\)/g),
      ...source.matchAll(/\bthis\.modeChoice\('[^']+',\s*'([^']+)'\)/g),
      ...source.matchAll(/\bthis\.navItem\(\d+,\s*'([^']+)'/g)].map(match => match[1]);
    for (const match of source.matchAll(/\bthis\.guideItem\(\d+,\s*'([^']+)',\s*'([^']+)'\)/g)) {
      keys.push(match[1], match[2]);
    }
    for (const key of keys) {
      for (const language of ['base', 'en', 'pl']) {
        assert.ok(strings[language].has(key), `${path}: missing ${language}:${key}`);
      }
    }
  }
});

test('Polish copy has no old English diagnostic or exercise-body text and preserves essential limits', () => {
  const polish = [...strings.pl.values()].join('\n');
  assert.doesNotMatch(polish,
    /No radio packet received|Packet processing failed|Network outage exercise|EXERCISE ONLY|Local emulator test transport|Technical result|MOCK TRANSPORTU/);
  assert.match(strings.pl.get('exercise_notice'), /nie jest to oficjalny alert/i);
  assert.match(strings.en.get('exercise_notice'), /not an official alert/i);
  assert.match(strings.pl.get('foreground_notice'), /przekazywanie jest wstrzymane/);
  assert.match(strings.en.get('foreground_notice'), /pauses when you leave the app/);
  assert.match(strings.pl.get('distance_notice'), /linii prostej/);
  assert.match(strings.pl.get('access_notice'), /nie.*sprawdzany.*bieżąco/);
  assert.match(strings.en.get('lab_explanation'), /without NearLink radio/);
});
