import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { parseToml } from './toml.mjs';
import { checkTokens, validateTheme } from './theme.mjs';
import { plainTones, launcherLook, listLook, osdLook, chipLook } from './voice.mjs';

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
// Files that still name them, with how many lines; a ratchet that fails only on a new offender, its entries struck as each file comes to read the table.
const LEFT = {
  'shell/DeenDuas.qml': 1,
  'shell/DeenHadith.qml': 7,
  'shell/DeenPrayer.qml': 1,
  'shell/DeenRead.qml': 2,
  'shell/DekhoBrowse.qml': 9,
  'shell/DekhoHome.qml': 7,
  'shell/DekhoPerson.qml': 3,
  'shell/DekhoReleases.qml': 1,
  'shell/DekhoStrip.qml': 2,
  'shell/DekhoTitle.qml': 6,
  'shell/Tailscale.qml': 1,
  'shell/lib/accounts.mjs': 1,
  'shell/lib/apps.mjs': 1,
  'shell/lib/tailscale.mjs': 1,
  'shell/lib/themes.mjs': 1,
  'shell/lib/youtube-look.mjs': 1,
};

const root = new URL('../..', import.meta.url).pathname;
function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) return f === 'node_modules' || f === 'testdata' ? [] : walk(p);
    return /\.(qml|mjs|js|css|html)$/.test(f) && !f.endsWith('.test.mjs') ? [p] : [];
  });
}

test('no file in shell/ names an Artboard light colour outside the plain table, but those still listed', () => {
  const pattern = new RegExp(LIGHT.map((h) => h.slice(1)).join('|'), 'i');
  const found = {};
  for (const p of walk(join(root, 'shell'))) {
    let text = readFileSync(p, 'utf8');
    if (p.endsWith('shell/lib/voice.mjs')) text = text.replace(/^const PLAIN = \{[\s\S]*?^\};$/m, '');
    const n = text.split('\n').filter((l) => pattern.test(l)).length;
    if (n) found[relative(root, p)] = n;
  }
  const grew = Object.entries(found).filter(([f, n]) => n > (LEFT[f] ?? 0)).map(([f, n]) => `${f}: ${n} (allowed ${LEFT[f] ?? 0})`);
  assert.deepEqual(grew, [], 'a file names an Artboard light colour; read it from plainTones(tokens)');
});
