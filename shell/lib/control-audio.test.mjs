import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { appStreams, appTitle, appRow, nextSink, devices, nextProfile, nextRoute, deviceParts } from './control-audio.mjs';

// The MacBook's two Built-in Audio cards, as pw-dump read them on 2026-10-30: 45 with off, HiFi and pro-audio, 46 with a route each way.
const dump = JSON.parse(readFileSync(new URL('./testdata/pw-dump-builtin.json', import.meta.url)));
const builtin = devices(dump);
const withProfile = (d, index) => ({ ...d, profile: d.profiles.find(p => p.index === index) });

const out = props => ({ 'media.class': 'Stream/Output/Audio', ...props });

test('a stream with an active link to a sink is an app, on that sink', () => {
  const streams = [{ id: 30, props: out({ 'application.name': 'Test Player' }) }];
  assert.deepEqual(appStreams(streams, [{ source: 30, target: 11, active: true }], [11, 12]), [{ id: 30, sink: 11 }]);
});

test('a stream whose link is not active, or goes to no sink, is no app', () => {
  const streams = [{ id: 30, props: out({}) }];
  assert.deepEqual(appStreams(streams, [{ source: 30, target: 11, active: false }], [11]), []);
  assert.deepEqual(appStreams(streams, [{ source: 30, target: 99, active: true }], [11]), []);
});

test('a capture stream is no app', () => {
  const streams = [{ id: 31, props: { 'media.class': 'Stream/Input/Audio', 'application.name': 'pw-record' } }];
  assert.deepEqual(appStreams(streams, [{ source: 31, target: 11, active: true }], [11]), []);
});

test('a filter chain, a loopback or a peak monitor is no app', () => {
  const links = [30, 31, 32].map(source => ({ source, target: 11, active: true }));
  const streams = [
    { id: 30, props: out({ 'node.description': 'MacBook Pro J493 Speakers DSP Out', 'node.passive': true, 'node.link-group': 'filter-chain-1484-19' }) },
    { id: 31, props: out({ 'node.link-group': 'loopback-1' }) },
    { id: 32, props: out({ 'stream.monitor': true }) },
  ];
  assert.deepEqual(appStreams(streams, links, [11]), []);
});

test('an app is titled by its application name, else its node description', () => {
  assert.equal(appTitle({ 'application.name': 'Test Player', 'node.description': 'x' }), 'Test Player');
  assert.equal(appTitle({ 'node.description': 'Bare stream', 'node.name': 'bare' }), 'Bare stream');
});

test("an app's detail is its output and volume, or muted", () => {
  assert.deepEqual(appRow({ title: 'Test Player', sink: 'Dots null sink', volume: 0.4, muted: false }), { title: 'Test Player', detail: 'Dots null sink · 40%' });
  assert.equal(appRow({ title: 'Test Player', sink: 'Dots null sink', volume: 0.4, muted: true }).detail, 'Dots null sink · muted');
});

test('the next output follows the current one and wraps from the last to the first', () => {
  assert.equal(nextSink([11, 12], 11), 12);
  assert.equal(nextSink([11, 12], 12), 11);
  assert.equal(nextSink([11, 12], 99), 11);
});

test('after HiFi comes pro-audio, and after pro-audio HiFi, never off', () => {
  assert.equal(builtin[45].profile.name, 'HiFi');
  assert.equal(nextProfile(builtin[45]), 2);
  assert.equal(nextProfile(withProfile(builtin[45], 2)), 1);
});

test('p skips a profile the device marks unavailable, and offers nothing with no other', () => {
  const d = { profiles: [{ index: 0, name: 'off' }, { index: 1, name: 'a2dp-sink', available: 'yes' }, { index: 2, name: 'headset-head-unit', available: 'no' }], profile: { index: 1 } };
  assert.equal(nextProfile(d), null);
});

test("r offers only available routes of the row's direction on its own card device", () => {
  // 46's only usable output route is the speakers', so the headphones' node has none and the speakers' none other.
  assert.equal(nextRoute(builtin[46], 'Output', 1), null);
  assert.equal(nextRoute(builtin[46], 'Output', 0), null);
  const plugged = { ...builtin[46], routes: builtin[46].routes.map(r => ({ ...r, devices: [0], available: 'yes' })) };
  assert.equal(nextRoute(plugged, 'Output', 0), 1);
  assert.equal(nextRoute({ ...plugged, active: [{ index: 1, direction: 'Output', device: 0 }] }, 'Output', 0), 0);
});

test("a device row's detail adds its profile and port", () => {
  const bt = { profile: { name: 'a2dp-sink-aac', description: 'High Fidelity Playback (A2DP Sink, codec AAC)' }, active: [] };
  assert.deepEqual(deviceParts(bt, 'Output', null), ['High Fidelity Playback (A2DP Sink, codec AAC)']);
});

// Beside the row's own default, a profile described as Default says nothing, so ALSA's HiFi reads by its name.
test('a profile described as Default is named instead', () => {
  assert.deepEqual(deviceParts(builtin[46], 'Output', 0), ['HiFi', 'Speakers']);
  assert.deepEqual(deviceParts(builtin[46], 'Output', 1), ['HiFi']);
});
