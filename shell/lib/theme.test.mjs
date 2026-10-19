import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseToml } from './toml.mjs';
import { validateTheme, checkTokens, renderNiri, renderFoot, renderFootArgs, renderFootOsc, contrast } from './theme.mjs';

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
  assert.match(kdl, /shadow \{\s*on\s*softness 0\s*spread 0\s*offset x=3 y=3\s*color "#1C1915"/);
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
  // A light theme fills [colors-light] and starts in it, so foot tells apps the truth about light and dark.
  assert.match(ini, /^\[main\]\ninitial-color-theme=light\n\[colors-light\]$/m);
  assert.doesNotMatch(ini, /colors-dark/);
  assert.match(ini, /^background=FAF6EC$/m);
  assert.match(ini, /^foreground=1C1915$/m);
  assert.match(ini, /^regular1=C8381E$/m);
});

test('foot\'s own chrome takes the theme too: cursor, selection, URLs, labels, search', () => {
  const ini = renderFoot(load('blueprint'));
  assert.match(ini, /^initial-color-theme=dark\n\[colors-dark\]$/m);
  assert.match(ini, /^cursor=0A1526 7FE3F0$/m);
  assert.match(ini, /^selection-foreground=0A1526$/m);
  assert.match(ini, /^selection-background=7FE3F0$/m);
  assert.match(ini, /^urls=7FE3F0$/m);
  assert.match(ini, /^jump-labels=0A1526 7FE3F0$/m);
  assert.match(ini, /^search-box-no-match=0A1526 FFB547$/m);
});

test('Inter is not a theme font: the themes draw with Maple Mono and Instrument Serif', () => {
  const bad = structuredClone(paper);
  bad.type.ui = 'Inter';
  assert.throws(() => validateTheme(bad), /type\.ui: "Inter"/);
  assert.deepEqual([load('artboard').type.display, load('artboard').type.ui], ['Maple Mono', 'Maple Mono']);
});

test('each theme names its voice, since the fonts no longer tell the themes apart', () => {
  assert.deepEqual(['paper', 'artboard', 'blueprint'].map((n) => load(n).type.voice), ['caps', 'plain', 'bracket']);
  const bad = structuredClone(paper);
  bad.type.voice = 'loud';
  assert.throws(() => validateTheme(bad), /type\.voice: "loud"/);
});

test('the footclient overrides say what the fragment says, one per line', () => {
  const t = load('artboard');
  const args = renderFootArgs(t).trim().split('\n');
  assert.equal(args[0], 'main.initial-color-theme=light');
  assert.ok(args.includes('colors-light.background=FFFFFF'));
  assert.ok(args.includes('colors-light.cursor=FFFFFF 3D5AFE'));
  const keys = renderFoot(t).split('\n').filter((l) => l.includes('=')).length;
  assert.equal(args.length, keys);
});

test('foot accepts the home foot.ini with each theme included', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dots-foot-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const home = readFileSync(new URL('../../home/dot_config/foot/foot.ini', import.meta.url), 'utf8');
  for (const name of ['paper', 'artboard', 'blueprint']) {
    writeFileSync(join(dir, 'theme.ini'), renderFoot(load(name)));
    writeFileSync(join(dir, 'foot.ini'), home.replace(/^include=.*$/m, `include=${join(dir, 'theme.ini')}`));
    execFileSync('foot', ['--check-config', '-c', join(dir, 'foot.ini')], { stdio: 'pipe' });
  }
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

test('Artboard has no border, a 2 px blue focus ring, a soft long shadow and radius 14', () => {
  const kdl = renderNiri(load('artboard'));
  assert.match(kdl, /border \{\s*off\s*\}/);
  assert.match(kdl, /focus-ring \{\s*on\s*width 2\s*active-color "#3D5AFE"/);
  assert.match(kdl, /shadow \{\s*on\s*softness 40\s*spread 0\s*offset x=0 y=18\s*color "#15171B2E"/);
  assert.match(kdl, /geometry-corner-radius 14/);
  assert.match(kdl, /spring damping-ratio=0\.72 stiffness=380/);
});

test('Blueprint frames the focused window in cyan, the others in #2E5A72, and glows only the focused one', () => {
  const kdl = renderNiri(load('blueprint'));
  assert.match(kdl, /border \{\s*on\s*width 1\s*active-color "#7FE3F0"\s*inactive-color "#2E5A72"/);
  assert.match(kdl, /focus-ring \{\s*off\s*\}/);
  assert.match(kdl, /shadow \{\s*on\s*softness 18\s*spread 0\s*offset x=0 y=0\s*color "#7FE3F040"\s*inactive-color "#00000000"/);
  assert.match(kdl, /geometry-corner-radius 0/);
});

test('a theme without shadow keys gets no shadow', () => {
  const t = load('paper');
  delete t.niri.shadow_color;
  assert.match(renderNiri(t), /shadow \{\s*off\s*\}/);
});

test('the foot OSC string sets the 16 colours, cursor and selection, then foreground and background', () => {
  const osc = renderFootOsc(load('blueprint'));
  assert.ok(osc.startsWith('\x1b]4;0;#1B2B44\x1b\\'));
  assert.ok(osc.includes('\x1b]4;15;#FFFFFF\x1b\\'));
  assert.ok(osc.includes('\x1b]12;#7FE3F0\x1b\\\x1b]17;#7FE3F0\x1b\\\x1b]19;#0A1526\x1b\\'));
  assert.ok(osc.endsWith('\x1b]10;#D6F4F8\x1b\\\x1b]11;#0A1526\x1b\\'));
});
