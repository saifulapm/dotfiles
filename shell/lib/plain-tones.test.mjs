import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { contrast } from './theme.mjs';
import { schemeTokens, schemeNames } from './colorscheme-file.mjs';
import { plainTones, launcherLook, listLook, osdLook, chipLook, islandLook } from './voice.mjs';
import { surfaceStyle } from './surface.mjs';

const SCHEMES = schemeNames();
const artboard = schemeTokens('artboard');

test("Artboard keeps its own board colours, before the tokens load too; every other scheme mixes its from its tokens", () => {
  const tones = { tint: '#EEF1FF', deep: '#2638C9', tile: '#F2F3F6', field: '#F6F7F9', thumb: '#E9ECF1', rule: '#E3E6EB', bar: '#6C83FF', online: '#1E8E5A', outline: '#8A909B', warn: '#B4380B', warnChip: '#FFF1E8', strong: '#2B2F36', card: '#FFFFFF', island: { head: '#A3A9B4', body: '#C9CED6', summary: '#FFFFFF', tile: '#2B2F36' } };
  assert.deepEqual(plainTones(artboard), tones);
  assert.deepEqual(plainTones(null), tones);
  const mocha = schemeTokens('catppuccin-mocha');
  const m = plainTones(mocha);
  assert.deepEqual([m.card, m.strong, m.online, m.outline, m.island.summary], [mocha.color.surface, mocha.color.ink, mocha.color.ok, mocha.color.muted, mocha.color.ink]);
  for (const n of SCHEMES.slice(1)) assert.notEqual(plainTones(schemeTokens(n)).tint, tones.tint, n);
});

test("the lit row is the scheme's tint with its deep text, in the launcher and every list", () => {
  for (const look of [launcherLook, listLook]) {
    for (const n of SCHEMES) {
      const t = plainTones(schemeTokens(n));
      assert.deepEqual([look(schemeTokens(n)).cursor.fill, look(schemeTokens(n)).cursor.text], [t.tint, t.deep], n);
    }
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
      const without = text.replace(/^const ARTBOARD = \{[\s\S]*?^\};$/m, '');
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

test("every scheme's island note, lease, toast and media controls read at 4.5:1 or more against the island's own fill", () => {
  for (const n of SCHEMES) {
    const t = schemeTokens(n);
    const fill = solid(surfaceStyle(t, 'island').fill);
    const note = islandLook(t);
    for (const part of ['head', 'summary', 'body', 'control']) {
      const ratio = contrast(solid(note[part]?.color), fill);
      assert.ok(ratio >= 4.5, `${n} ${part} ${note[part].color} on ${fill}: ${ratio.toFixed(2)}`);
    }
  }
});

// Muted words are the scheme's own token, which only ink is held to 4.5:1 against, so they are not checked here.
test("every scheme's lit row reads its text and detail at 4.5:1, its mode pill its word, and its key hints their keys on the surface", () => {
  for (const n of SCHEMES) {
    const t = schemeTokens(n);
    const l = launcherLook(t);
    const pairs = { text: [l.cursor.text, l.cursor.fill], detail: [l.cursor.detail, l.cursor.fill], pill: [l.label.color, l.label.fill], chipKey: [l.chip.key, t.color.surface], tileName: [t.color.ink, plainTones(t).field] };
    for (const [what, [fg, bg]] of Object.entries(pairs)) {
      const ratio = contrast(solid(fg), solid(bg));
      assert.ok(ratio >= 4.5, `${n} ${what} ${fg} on ${bg}: ${ratio.toFixed(2)}`);
    }
  }
});

// 2XV8P1VJ: backing the tint onto the surface kept the words readable and lost the lit row; Artboard's, the weakest seen as lit, is 1.125:1.
test("every scheme's lit row stands off its surface at 1.1:1 or more", () => {
  for (const n of SCHEMES) {
    const t = schemeTokens(n);
    const ratio = contrast(solid(launcherLook(t).cursor.fill), t.color.surface);
    assert.ok(ratio >= 1.1, `${n} lit row ${launcherLook(t).cursor.fill} on ${t.color.surface}: ${ratio.toFixed(3)}`);
  }
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

test("every word drawn on the tint or a pill reads at 4.5:1 there: the launcher pill, YouTube's tint word", async () => {
  const { youtubeLook } = await import('./youtube-look.mjs');
  for (const n of SCHEMES) {
    const t = schemeTokens(n);
    const yt = youtubeLook(t).tint;
    for (const [what, fg, bg] of [['pill', listLook(t).label.color, listLook(t).label.fill], ['youtube', yt.word, yt.tint]]) {
      const ratio = contrast(solid(fg), solid(bg));
      assert.ok(ratio >= 4.5, `${n} ${what} ${fg} on ${bg}: ${ratio.toFixed(2)}`);
    }
  }
});
