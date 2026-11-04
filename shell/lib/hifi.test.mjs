import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateTheme, checkTokens } from './theme.mjs';
import { HIFI, isHifi, lamp, glass, tuningScale, switchKind, sweepAt, warmLamp } from './hifi.mjs';

const load = (name) => validateTheme(parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8')));
// The shell reads Hi-Fi through checkTokens, as the bracket voice plus engraved.
const hifi = checkTokens(load('hi-fi'));
const blueprint = checkTokens(load('blueprint'));
const paper = checkTokens(load('paper'));
const artboard = checkTokens(load('artboard'));
const frost = checkTokens(load('frost'));

test("Hi-Fi's own parts key on voice engraved, never on the theme's name", () => {
  assert.equal(isHifi(hifi), true);
  assert.equal(isHifi(blueprint), false);
  assert.equal(isHifi(null), false);
  assert.equal(isHifi(Object.assign({}, blueprint, { type: Object.assign({}, blueprint.type, { engraved: true }) })), true);
});

test('the board colours no token carries', () => {
  assert.deepEqual(HIFI, { unlit: '#3C3836', lit: '#413A29', groove: '#0E0F10', walnut: '#3A2A1F' });
});

test('a lamp is lit amber with a glow, unlit #3C3836 without one, and red or green for a deadline or the theme in use', () => {
  assert.deepEqual(lamp(hifi, 'lit'), { size: 6, color: '#FABD2F', glow: '#FABD2F' });
  assert.deepEqual(lamp(hifi, 'unlit'), { size: 6, color: '#3C3836', glow: 'transparent' });
  assert.deepEqual(lamp(hifi, 'red', 7), { size: 7, color: '#FB4934', glow: '#FB4934' });
  assert.deepEqual(lamp(hifi, 'green'), { size: 6, color: '#B8BB26', glow: '#B8BB26' });
});

test('glass is the glass token in a 1 px line frame under a 1 px highlight of ink at 6 %', () => {
  assert.deepEqual(glass(hifi), { fill: '#141617', border: '#504945', borderWidth: 1, highlight: '#0FEBDBB2' });
});

test('the tuning scale ticks every 8 px at 28 % and every 40 px at 50 %, under a 2 px red pointer', () => {
  const s = tuningScale(hifi, 100, 0.5);
  assert.deepEqual(
    s.ticks.map((t) => [t.x, t.major]),
    [[0, true], [8, false], [16, false], [24, false], [32, false], [40, true], [48, false], [56, false], [64, false], [72, false], [80, true], [88, false], [96, false]],
  );
  assert.deepEqual(s.ticks[0].color, '#80FABD2F');
  assert.deepEqual(s.ticks[1].color, '#47FABD2F');
  assert.deepEqual(s.pointer, { x: 49, width: 2, color: '#FB4934' });
  // The pointer stays on the scale at either end.
  assert.equal(tuningScale(hifi, 100, 1).pointer.x, 98);
  assert.equal(tuningScale(hifi, 100, -1).pointer.x, 0);
  assert.deepEqual(tuningScale(hifi, 0, 0.5).ticks, []);
});

test('a switch into or out of Hi-Fi sweeps; every other pair plays the outgoing theme\'s motion', () => {
  assert.equal(switchKind(blueprint, hifi), 'sweep');
  assert.equal(switchKind(hifi, paper), 'sweep');
  assert.equal(switchKind(paper, blueprint), 'slide');
  assert.equal(switchKind(blueprint, artboard), 'scan');
  assert.equal(switchKind(artboard, paper), 'zoom');
});

test('a switch into or out of Frost plays the frost switch, and between Hi-Fi and Frost the incoming theme\'s', () => {
  assert.equal(switchKind(paper, frost), 'frost');
  assert.equal(switchKind(frost, blueprint), 'frost');
  assert.equal(switchKind(frost, artboard), 'frost');
  assert.equal(switchKind(hifi, frost), 'frost');
  assert.equal(switchKind(frost, hifi), 'sweep');
});

test('the sweep pointer eases in and out, and the lamps warm over the last 60 of its 220 ms', () => {
  assert.deepEqual(sweepAt(0), { pointer: 0, warmth: 0 });
  assert.deepEqual(sweepAt(0.25), { pointer: 0.0625, warmth: 0 });
  assert.deepEqual(sweepAt(0.5), { pointer: 0.5, warmth: 0 });
  assert.deepEqual(sweepAt(0.75), { pointer: 0.9375, warmth: 5 / 60 });
  assert.equal(sweepAt(160 / 220).warmth, 0);
  assert.ok(Math.abs(sweepAt(190 / 220).warmth - 0.5) < 1e-9);
  assert.deepEqual(sweepAt(1), { pointer: 1, warmth: 1 });
});

test('a warming lamp blends from unlit to its own colour, and a warm one is the plain lamp', () => {
  assert.deepEqual(warmLamp(hifi, 'lit', 6, 0), { size: 6, color: '#3C3836', glow: '#FABD2F' });
  assert.deepEqual(warmLamp(hifi, 'lit', 6, 0.5), { size: 6, color: '#9B7B33', glow: '#FABD2F' });
  assert.deepEqual(warmLamp(hifi, 'red', 7, 1), { size: 7, color: '#FB4934', glow: '#FB4934' });
  assert.deepEqual(warmLamp(hifi, 'unlit', 6, 0.5), { size: 6, color: '#3C3836', glow: 'transparent' });
});
