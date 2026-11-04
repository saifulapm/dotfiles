import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseToml } from './toml.mjs';
import { validateTheme, checkTokens, renderNiri, renderFoot, renderFootOsc } from './theme.mjs';
import { renderHelix, renderChromiumTheme, renderGtkSettings, renderZathura, renderNewtabCss } from './apps.mjs';

const render = new URL('./theme-render.mjs', import.meta.url).pathname;
const load = (n) => parseToml(readFileSync(new URL(`../../themes/${n}/theme.toml`, import.meta.url), 'utf8'));
const frost = () => validateTheme(load('frost'));
const sha = (b) => createHash('sha256').update(b).digest('hex');

// Every fragment the four older themes rendered before Frost, by hash; the copies of shell/newtab's own files and the card list change on purpose.
const GOLDEN = JSON.parse(readFileSync(new URL('./testdata/theme-goldens-frost.json', import.meta.url), 'utf8'));

function renderInto(state, name) {
  const r = spawnSync(process.execPath, [render, name], { env: Object.assign({}, process.env, { XDG_STATE_HOME: state }), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return join(state, 'dots/theme-out');
}

function files(dir, rel = '') {
  return readdirSync(join(dir, rel)).flatMap((f) => (statSync(join(dir, rel, f)).isDirectory() ? files(dir, join(rel, f)) : [join(rel, f)]));
}

test('Paper, Artboard, Blueprint and Hi-Fi render every fragment byte for byte as before Frost', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-golden-frost-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  for (const name of ['paper', 'artboard', 'blueprint', 'hi-fi']) {
    const out = renderInto(join(state, name), name);
    const got = {};
    for (const f of files(out)) if (f in GOLDEN[name]) got[f] = sha(readFileSync(join(out, f)));
    assert.deepEqual(got, GOLDEN[name], `${name}: a fragment changed`);
  }
});

test('Frost validates as dark Nord: frost paper, a hairline frame, ease motion, the plain voice in Inter', () => {
  const t = frost();
  assert.equal(t.name, 'frost');
  assert.equal(t.mode, 'dark');
  assert.deepEqual([t.primitive.paper, t.primitive.frame, t.primitive.shadow, t.primitive.corner, t.primitive.motion], ['frost', 'hairline', 'none', 'round', 'ease']);
  assert.deepEqual([t.type.display, t.type.ui, t.type.mono, t.type.voice], ['Inter', 'Inter', 'Maple Mono', 'plain']);
  assert.deepEqual([t.color.paper, t.color.surface, t.color.ink, t.color.muted, t.color.line, t.color.accent], ['#2E3440', '#3B4252', '#D8DEE9', '#AEB7C6', '#434C5E', '#88C0D0']);
  assert.equal(t.color.glass, '#3B4252D9');
  assert.equal(t.color.edge, '#ECEFF424');
  assert.equal(t.syntax.comment, '#7B88A1');
  assert.equal(t.color.ansi[8], '#AEB7C6');
});

test('glass may carry alpha last, edge is optional, and a short edge fails naming color.edge', () => {
  const short = load('frost');
  short.color.edge = '#ECEFF42';
  assert.throws(() => validateTheme(short), /color\.edge: "#ECEFF42" is not #RRGGBB or #RRGGBBAA/);
  const glass = load('frost');
  glass.color.glass = '#3B4252D';
  assert.throws(() => validateTheme(glass), /color\.glass: "#3B4252D" is not #RRGGBB or #RRGGBBAA/);
  const none = load('frost');
  delete none.color.edge;
  assert.equal('edge' in validateTheme(none).color, false);
  assert.equal('edge' in validateTheme(load('artboard')).color, false);
});

test('shell.json and themes.json carry Frost\'s glass and edge in Qt\'s #AARRGGBB, which the shell\'s own check accepts', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-frost-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const out = renderInto(state, 'frost');
  const shell = JSON.parse(readFileSync(join(out, 'shell.json'), 'utf8'));
  assert.deepEqual([shell.color.glass, shell.color.edge, shell.color.surface], ['#D93B4252', '#24ECEFF4', '#3B4252']);
  assert.equal(checkTokens(shell).color.glass, '#D93B4252');
  const cards = JSON.parse(readFileSync(join(out, 'themes.json'), 'utf8'));
  assert.deepEqual(cards.map((c) => c.name), ['paper', 'artboard', 'blueprint', 'frost', 'hi-fi']);
  const card = cards.find((c) => c.name === 'frost');
  assert.deepEqual([card.color.glass, card.color.edge], ['#D93B4252', '#24ECEFF4']);
  assert.equal(cards.find((c) => c.name === 'hi-fi').color.glass, '#141617');
});

test('Inter is a package on every machine, since Frost draws the shell in it', () => {
  const block = readFileSync(new URL('../../packages.toml', import.meta.url), 'utf8').split(/^\[\[package\]\]$/m).find((b) => /^name = "rsms-inter-fonts"$/m.test(b));
  assert.match(block ?? '', /^arch = "all"$/m);
});

test('Frost frames windows in a 1 px frost-blue border with 10 px corners, 20 px gaps and no shadow', () => {
  const kdl = renderNiri(frost());
  assert.match(kdl, /border \{\s*on\s*width 1\s*active-color "#88C0D0"\s*inactive-color "#434C5E"/);
  assert.match(kdl, /shadow \{\s*off\s*\}/);
  assert.match(kdl, /gaps 20\n/);
  assert.match(kdl, /window-rule \{\s*geometry-corner-radius 10\s/);
  assert.match(kdl, /window-open \{\s*duration-ms 200\s*curve "ease-out-cubic"\s*\}/);
  assert.match(kdl, /window-close \{\s*duration-ms 90\s*curve "linear"\s*\}/);
});

// niri turns xray on by itself behind a region a surface asks to blur; a layer-rule's xray would show the paper over every window behind the full-screen shell layers whenever no region is asked for.
test('no theme\'s niri.kdl holds a layer-rule or background effect, Frost included', () => {
  for (const name of ['paper', 'artboard', 'blueprint', 'frost', 'hi-fi']) assert.doesNotMatch(renderNiri(validateTheme(load(name))), /background-effect|layer-rule/, name);
});

test('niri accepts Frost\'s fragment', (t) => {
  if (spawnSync('niri', ['--version']).status !== 0) return t.skip('no niri here');
  const dir = mkdtempSync(join(tmpdir(), 'dots-frost-niri-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, 'niri.kdl'), renderNiri(frost()));
  const r = spawnSync('niri', ['validate', '-c', join(dir, 'niri.kdl')], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
});

test('Frost\'s apps are dark Nord: foot and an open foot, helix, Chromium and GTK', () => {
  const t = frost();
  const foot = renderFoot(t);
  assert.match(foot, /initial-color-theme=dark/);
  assert.match(foot, /\[colors-dark\][\s\S]*background=3B4252[\s\S]*regular1=BF616A[\s\S]*bright0=AEB7C6/);
  const osc = renderFootOsc(t);
  for (const seq of ['4;1;#BF616A', '4;8;#AEB7C6', '11;#3B4252']) assert.ok(osc.includes(`\x1b]${seq}\x1b\\`), seq);
  assert.match(renderHelix(t), /"comment" = \{ fg = "#7b88a1"/);
  const chrome = JSON.parse(renderChromiumTheme(t)).theme.colors;
  assert.deepEqual([chrome.frame, chrome.toolbar], [[46, 52, 64], [59, 66, 82]]);
  assert.match(renderGtkSettings(t), /gtk-application-prefer-dark-theme=true/);
  assert.match(renderZathura(t), /set recolor true[\s\S]*set recolor-keephue true|set recolor-keephue true[\s\S]*set recolor true/);
});

test('Frost\'s new tab takes the plain board colours from its own row, dark, and Artboard\'s stay', () => {
  const css = renderNewtabCss(frost());
  for (const [k, v] of [['tile', '#434C5E'], ['field', '#323845'], ['tint', '#475666'], ['deep', '#ECEFF4']]) assert.match(css, new RegExp(`--${k}: ${v};`), k);
  const art = renderNewtabCss(validateTheme(load('artboard')));
  for (const [k, v] of [['tile', '#F2F3F6'], ['field', '#F6F7F9'], ['tint', '#EEF1FF'], ['deep', '#2638C9']]) assert.match(art, new RegExp(`--${k}: ${v};`), k);
});
