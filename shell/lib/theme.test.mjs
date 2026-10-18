import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { validateTheme, checkTokens, renderNiri, renderFoot, contrast } from './theme.mjs';

const paper = parseToml(readFileSync(new URL('../../themes/paper/theme.toml', import.meta.url), 'utf8'));

test('the Paper theme validates into its tokens', () => {
  const t = validateTheme(paper);
  assert.equal(t.name, 'paper');
  assert.equal(t.mode, 'light');
  assert.equal(t.color.paper, '#F1E9D8');
  assert.equal(t.color.ink, '#1C1915');
  assert.equal(t.color.ansi.length, 16);
  assert.equal(t.primitive.paper, 'grain');
});

test('a primitive outside its menu is refused by name', () => {
  const bad = structuredClone(paper);
  bad.primitive.frame = 'dashed';
  assert.throws(() => validateTheme(bad), /primitive\.frame: "dashed"/);
});

test('a colour that is not #RRGGBB is refused by name', () => {
  const bad = structuredClone(paper);
  bad.color.ink = 'black';
  assert.throws(() => validateTheme(bad), /color\.ink/);
});

test('ansi must hold 16 colours', () => {
  const bad = structuredClone(paper);
  bad.color.ansi = bad.color.ansi.slice(0, 8);
  assert.throws(() => validateTheme(bad), /color\.ansi/);
});

test('the niri fragment sets the paper as background and the ink frame', () => {
  const kdl = renderNiri(validateTheme(paper));
  assert.match(kdl, /background-color "#F1E9D8"/);
  assert.match(kdl, /focus-ring \{\s*off\s*\}/);
  assert.match(kdl, /border \{\s*on\s*width 1\s*active-color "#1C1915"/);
  assert.match(kdl, /softness 0/);
  assert.match(kdl, /offset x=2 y=2/);
  assert.match(kdl, /geometry-corner-radius 0/);
});

test('windows sit 56 px down and 32 px in, clear of the margins, with niri drawing their frames', () => {
  const kdl = renderNiri(validateTheme(paper));
  assert.match(kdl, /struts \{\s*top 32\s*bottom 4\s*left 8\s*right 8\s*\}/);
  assert.match(kdl, /^prefer-no-csd$/m);
});

test('rendered tokens check out, and a bad colour in them is refused by name', () => {
  const t = validateTheme(paper);
  assert.deepEqual(checkTokens(JSON.parse(JSON.stringify(t))), t);
  assert.throws(() => checkTokens({ ...t, color: { ...t.color, paper: 'notacolor' } }), /color\.paper/);
});

test('the foot fragment carries the palette', () => {
  const ini = renderFoot(validateTheme(paper));
  assert.match(ini, /^\[colors\]$/m);
  assert.match(ini, /^background=FAF6EC$/m);
  assert.match(ini, /^foreground=1C1915$/m);
  assert.match(ini, /^regular1=C8381E$/m);
});

const load = (name) => validateTheme(parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8')));

test('muted text reads at 4.5:1 or more on each paper', () => {
  for (const name of ['paper', 'artboard', 'blueprint']) {
    const t = load(name);
    assert.ok(contrast(t.color.muted, t.color.paper) >= 4.5, `${name}: ${contrast(t.color.muted, t.color.paper)}`);
  }
});

test('contrast is the WCAG ratio, either way round', () => {
  assert.equal(contrast('#000000', '#FFFFFF'), 21);
  assert.equal(contrast('#FFFFFF', '#000000'), 21);
  assert.equal(contrast('#777777', '#777777'), 1);
});

test('the Artboard and Blueprint themes carry their canvas tokens', () => {
  const a = load('artboard');
  assert.deepEqual([a.mode, a.color.paper, a.color.surface, a.primitive.paper, a.primitive.corner], ['light', '#E4E6EA', '#FFFFFF', 'dots', 'round']);
  assert.deepEqual([a.niri.gaps, a.niri.ring_width, a.niri.ring_color], [28, 2, '#3D5AFE']);
  const b = load('blueprint');
  assert.deepEqual([b.mode, b.color.paper, b.color.surface, b.color.ink, b.primitive.frame], ['dark', '#0C1A2E', '#0A1526', '#D6F4F8', 'glow']);
  assert.deepEqual([b.niri.border_inactive, b.niri.shadow_color, b.type.ui], ['#2E5A72', '#7FE3F040', 'Maple Mono']);
});

test('a niri colour that is not #RRGGBB or #RRGGBBAA is refused by name', () => {
  const bad = structuredClone(paper);
  bad.niri.shadow_color = 'ink';
  assert.throws(() => validateTheme(bad), /niri\.shadow_color/);
});
