import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { contrast } from './theme.mjs';
import { schemeTokens } from './colorscheme-file.mjs';
import { plainTones, launcherLook, listLook, osdLook, chipLook, islandLook } from './voice.mjs';
import { surfaceStyle } from './surface.mjs';

const SCHEMES = ['artboard', 'catppuccin-mocha', 'github-light', 'gruvbox-dark', 'rose-pine-dawn'];
const artboard = schemeTokens('artboard');

test("the plain voice's board colours are Artboard's for every scheme, and before the tokens load", () => {
  const tones = { tint: '#EEF1FF', deep: '#2638C9', tile: '#F2F3F6', field: '#F6F7F9', thumb: '#E9ECF1', rule: '#E3E6EB', bar: '#6C83FF', online: '#1E8E5A', outline: '#8A909B', warn: '#B4380B', warnChip: '#FFF1E8', strong: '#2B2F36', card: '#FFFFFF', island: { head: '#A3A9B4', body: '#C9CED6', summary: '#FFFFFF', tile: '#2B2F36' } };
  for (const n of SCHEMES) assert.deepEqual(plainTones(schemeTokens(n)), tones, n);
  assert.deepEqual(plainTones(null), tones);
});

test("the lit row is the tint with deep text, in the launcher and every list", () => {
  for (const look of [launcherLook, listLook]) {
    for (const n of SCHEMES) assert.deepEqual([look(schemeTokens(n)).cursor.fill, look(schemeTokens(n)).cursor.text], ['#EEF1FF', '#2638C9'], n);
  }
  assert.equal(launcherLook(artboard).name.font, 'Maple Mono');
  assert.equal(launcherLook(artboard).keyChip.fill, '#F2F3F6');
});

test("the meters fill in the table's periwinkle once the tokens load, and in the accent before", () => {
  assert.equal(osdLook(artboard).lit.color, '#6C83FF');
  assert.equal(osdLook(null).lit.color, 'white');
  assert.equal(chipLook(artboard).empty.color, '#6C83FF');
});

// Artboard's light board colours; only the plain table may name them, so every surface reads them from plainTones(tokens).
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
  let table = false;
  for (const p of walk(join(root, 'shell'))) {
    let text = readFileSync(p, 'utf8');
    if (p.endsWith('shell/lib/voice.mjs')) {
      const without = text.replace(/^const PLAIN = \{[\s\S]*?^\};$/m, '');
      table = without !== text;
      text = without;
    }
    const n = text.split('\n').filter((l) => pattern.test(l)).length;
    if (n) found[relative(root, p)] = n;
  }
  assert.equal(table, true, 'voice.mjs holds the plain table');
  assert.deepEqual(found, {}, 'a file names an Artboard light colour; read it from plainTones(tokens)');
});

// Text is read against the fill drawn behind it: the island and the lit row keep 4.5:1.
const solid = (hex) => hex.slice(0, 7);

test("Artboard's island note reads at 4.5:1 or more against the island's own fill", () => {
  const style = surfaceStyle(artboard, 'island');
  const note = islandLook(artboard);
  const ratios = ['head', 'summary', 'body'].map((part) => Number(contrast(solid(note[part].color || style.text), solid(style.fill)).toFixed(2)));
  assert.deepEqual(ratios, [7.6, 17.94, 11.35]);
});

test("Artboard's lit row reads its detail at 4.5:1, and its mode pill its word", () => {
  const l = launcherLook(artboard);
  const detail = contrast(solid(l.cursor.detail), solid(l.cursor.fill));
  const pill = contrast(solid(l.label.color), solid(l.label.fill));
  assert.ok(detail >= 4.5, `detail ${l.cursor.detail} on ${l.cursor.fill}: ${detail.toFixed(2)}`);
  assert.ok(pill >= 4.5, `pill ${l.label.color} on ${l.label.fill}: ${pill.toFixed(2)}`);
});

// A plain branch's white is Artboard's card; on a dark scheme it is a light slab, so it reads the table's card.
test('no shell surface draws a literal white on a plain branch', () => {
  const found = [];
  for (const p of walk(join(root, 'shell')).filter((f) => f.endsWith('.qml'))) {
    readFileSync(p, 'utf8').split('\n').forEach((l, i) => {
      if (/plain \? "(white|#fff|#ffffff)"/i.test(l)) found.push(`${relative(root, p)}:${i + 1}`);
    });
  }
  assert.deepEqual(found, []);
});
