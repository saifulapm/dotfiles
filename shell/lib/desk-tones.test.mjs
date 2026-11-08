import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deskTokens, plainTones, listLook, onDesk } from './voice.mjs';
import { schemeTokens, schemeNames } from './colorscheme-file.mjs';
import { contrast } from './theme.mjs';
import { mix } from './notes-look.mjs';

// An app window is clear on the desk like a terminal, so its words are the scheme's moved to read there, and its fills are veils QML draws over whatever lies under them.
const qml = (s) => /^#[0-9A-F]{8}$/.test(s);
const alpha = (s) => parseInt(s.slice(1, 3), 16) / 255;
const rgb = (s) => `#${s.slice(3)}`;
const grounds = (t) => [t.color.paper, t.paper.grade.from, t.paper.grade.to];

test("an app's tokens take the paper as surface and the scheme's words as onDesk moves them, ink on past its own tiles", () => {
  const t = schemeTokens('gruvbox-material-dark');
  const d = deskTokens(t);
  assert.equal(d.desk, true);
  assert.equal(d.color.surface, t.color.paper);
  for (const k of ['muted', 'accent', 'danger', 'ok']) assert.equal(d.color[k], onDesk(t, t.color[k]), k);
  assert.ok(contrast(d.color.ink, t.color.paper) >= contrast(onDesk(t, t.color.ink), t.color.paper), 'ink moves at least as far as onDesk takes it');
  assert.equal(t.color.surface, '#282828', 'the tokens themselves are left alone');
  assert.equal(deskTokens(null), null);
});

test("an app's fills are QML veils of the ink, and its lit row a veil of the accent, Artboard too", () => {
  for (const n of ['artboard', 'gruvbox-material-dark']) {
    const d = deskTokens(schemeTokens(n));
    const tones = plainTones(d);
    for (const [k, a] of [['tile', 0.06], ['field', 0.04], ['thumb', 0.09], ['rule', 0.12], ['card', 0.04]]) {
      assert.ok(qml(tones[k]), `${n} ${k} ${tones[k]}`);
      assert.equal(rgb(tones[k]), d.color.ink.toUpperCase(), `${n} ${k}`);
      assert.ok(Math.abs(alpha(tones[k]) - a) < 0.005, `${n} ${k} alpha`);
    }
    assert.ok(qml(tones.tint) && rgb(tones.tint) === d.color.accent.toUpperCase(), `${n} tint ${tones.tint}`);
    assert.match(tones.tintSolid, /^#[0-9A-F]{6}$/, 'a solid tint for the contrast walks');
  }
});

// A veil's colour is what lies under it mixed with the veil, so a word on it must read over the paper and over both ends of the field.
test("every scheme's words read on its app veils wherever they lie: ink on a tile, the lit row's word and detail on the tint", () => {
  for (const n of schemeNames()) {
    const d = deskTokens(schemeTokens(n));
    const tones = plainTones(d);
    const l = listLook(d);
    for (const g of grounds(d)) {
      const on = (veil) => mix(g, rgb(veil), alpha(veil)).toUpperCase();
      for (const [what, fg, veil] of [['ink on tile', d.color.ink, tones.tile], ['ink on field', d.color.ink, tones.field], ['deep on tint', tones.deep, tones.tint], ['detail on tint', l.cursor.detail, tones.tint]]) {
        const r = contrast(fg, on(veil));
        assert.ok(r >= 4.5, `${n} ${what} ${fg} over ${g}: ${r.toFixed(2)}`);
      }
    }
  }
});
