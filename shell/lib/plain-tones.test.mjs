import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { parseToml } from './toml.mjs';
import { checkTokens, validateTheme, contrast } from './theme.mjs';
import { plainTones, launcherLook, listLook, osdLook, chipLook, islandLook } from './voice.mjs';
import { surfaceStyle } from './surface.mjs';

const load = (n) => checkTokens(validateTheme(parseToml(readFileSync(new URL(`../../themes/${n}/theme.toml`, import.meta.url), 'utf8'))));
const frost = load('frost');
const artboard = load('artboard');

test('the plain voice takes its board colours from its theme: Frost its own, Artboard and any other plain theme Artboard\'s', () => {
  assert.deepEqual([plainTones(frost).tint, plainTones(frost).deep, plainTones(frost).tile], ['#475666', '#ECEFF4', '#434C5E']);
  assert.deepEqual([plainTones(artboard).tint, plainTones(artboard).deep, plainTones(artboard).tile], ['#EEF1FF', '#2638C9', '#F2F3F6']);
  assert.deepEqual(plainTones(null), plainTones(artboard));
  assert.deepEqual(Object.keys(plainTones(frost)), Object.keys(plainTones(artboard)));
});

test('Frost\'s lit row is opaque #475666 with #ECEFF4 text, in the launcher and every list; Artboard keeps its tint', () => {
  for (const look of [launcherLook, listLook]) {
    assert.deepEqual([look(frost).cursor.fill, look(frost).cursor.text], ['#475666', '#ECEFF4']);
    assert.deepEqual([look(artboard).cursor.fill, look(artboard).cursor.text], ['#EEF1FF', '#2638C9']);
  }
  assert.equal(launcherLook(frost).name.font, 'Inter');
  assert.equal(launcherLook(frost).keyChip.fill, '#434C5E');
});

test('Frost\'s meters fill in its accent, not Artboard\'s periwinkle', () => {
  assert.equal(osdLook(frost).lit.color, '#88C0D0');
  assert.equal(osdLook(artboard).lit.color, '#6C83FF');
  assert.equal(chipLook(frost).empty.color, '#88C0D0');
});

// Artboard's light board colours, which on Frost's dark glass would draw light tints; only the plain table may name them.
const LIGHT = ['#EEF1FF', '#2638C9', '#F2F3F6', '#F6F7F9', '#6C83FF', '#E3E6EB', '#E9ECF1', '#1E8E5A', '#8A909B', '#B4380B', '#FFF1E8'];
const root = new URL('../..', import.meta.url).pathname;
function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) return f === 'node_modules' || f === 'testdata' ? [] : walk(p);
    return /\.(qml|mjs|js|css|html)$/.test(f) && !f.endsWith('.test.mjs') ? [p] : [];
  });
}

test('no file in shell/ names an Artboard light colour outside the plain table', () => {
  const pattern = new RegExp(LIGHT.map((h) => h.slice(1)).join('|'), 'i');
  const found = {};
  for (const p of walk(join(root, 'shell'))) {
    let text = readFileSync(p, 'utf8');
    if (p.endsWith('shell/lib/voice.mjs')) text = text.replace(/^const PLAIN = \{[\s\S]*?^\};$/m, '');
    const n = text.split('\n').filter((l) => pattern.test(l)).length;
    if (n) found[relative(root, p)] = n;
  }
  assert.deepEqual(found, {}, 'a file names an Artboard light colour; read it from plainTones(tokens)');
});

// Text is read against the fill drawn behind it: every theme's island and lit row keep 4.5:1, so a dark theme's light ink never fills a slab under light text.
const ALL = ['paper', 'artboard', 'blueprint', 'frost', 'hi-fi'].map(load);
const solid = (hex) => hex.slice(0, 7);

test('every theme\'s island note reads at 4.5:1 or more against the island\'s own fill', () => {
  const low = [];
  for (const t of ALL) {
    const style = surfaceStyle(t, 'island');
    const note = islandLook(t);
    for (const part of ['head', 'summary', 'body']) {
      const color = note[part].color || style.text;
      const r = contrast(solid(color), solid(style.fill));
      if (r < 4.5) low.push(`${t.name} ${part} ${color} on ${style.fill}: ${r.toFixed(2)}`);
    }
  }
  assert.deepEqual(low, []);
});

test('every theme\'s lit row reads its detail at 4.5:1, and a plain mode pill its word', () => {
  const low = [];
  for (const t of ALL) {
    const l = launcherLook(t);
    const r = contrast(solid(l.cursor.detail), solid(l.cursor.fill));
    if (r < 4.5) low.push(`${t.name} detail ${l.cursor.detail} on ${l.cursor.fill}: ${r.toFixed(2)}`);
    if (l.label.kind === 'pill') {
      const p = contrast(solid(l.label.color), solid(l.label.fill));
      if (p < 4.5) low.push(`${t.name} pill ${l.label.color} on ${l.label.fill}: ${p.toFixed(2)}`);
    }
  }
  assert.deepEqual(low, []);
});

// A plain branch's white is Artboard's card; on Frost it is a light slab, so it reads the table's card, white only in Artboard.
test('no shell surface draws a literal white on a plain branch', () => {
  const found = [];
  for (const p of walk(join(root, 'shell')).filter((f) => f.endsWith('.qml'))) {
    readFileSync(p, 'utf8').split('\n').forEach((l, i) => {
      if (/plain \? "(white|#fff|#ffffff)"/i.test(l)) found.push(`${relative(root, p)}:${i + 1}`);
    });
  }
  assert.deepEqual(found, []);
});
