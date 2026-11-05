import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { validateTheme, checkTokens, renderNiri, renderFoot, renderFootArgs, renderFootOsc, contrast } from './theme.mjs';
import { loadScheme, schemeNames } from './colorscheme-file.mjs';

const SCHEMES = schemeNames();
const artboard = loadScheme('artboard');
const gruvbox = loadScheme('gruvbox-dark');
// A scheme's tokens back in the document shape the validator reads.
const doc = (t) => ({ meta: { name: t.name, mode: t.mode }, ...structuredClone({ color: t.color, syntax: t.syntax, primitive: t.primitive, paper: t.paper, type: t.type, niri: t.niri }) });

test('a scheme on the one design validates into its tokens', () => {
  const t = validateTheme(doc(artboard));
  assert.deepEqual([t.name, t.mode, t.color.paper, t.color.ink], ['artboard', 'light', '#E4E6EA', '#15171B']);
  assert.deepEqual(t.primitive, { paper: 'dots', frame: 'ink', shadow: 'none', corner: 'square', motion: 'spring' });
  assert.deepEqual([t.type.display, t.type.ui, t.type.mono, t.type.voice], ['Maple Mono', 'Maple Mono', 'Maple Mono', 'plain']);
});

test('a primitive, font or voice other than the one design is refused by name', () => {
  for (const [k, v] of [['paper', 'grid'], ['frame', 'none'], ['shadow', 'soft'], ['corner', 'round'], ['motion', 'snappy']]) {
    const bad = doc(artboard);
    bad.primitive[k] = v;
    assert.throws(() => validateTheme(bad), new RegExp(`primitive\\.${k}: "${v}"`), k);
  }
  const font = doc(artboard);
  font.type.ui = 'Inter';
  assert.throws(() => validateTheme(font), /type\.ui: "Inter" is not Maple Mono/);
  const voice = doc(artboard);
  voice.type.voice = 'caps';
  assert.throws(() => validateTheme(voice), /type\.voice: "caps" is not plain/);
});

test('a colour that is not #RRGGBB is refused by name, and ansi must hold 16', () => {
  const bad = doc(artboard);
  bad.color.paper = 'cream';
  assert.throws(() => validateTheme(bad), /color\.paper: "cream"/);
  const short = doc(artboard);
  short.color.ansi = short.color.ansi.slice(0, 8);
  assert.throws(() => validateTheme(short), /color\.ansi must hold 16/);
});

test('every scheme carries its code colours, each #RRGGBB', () => {
  const bad = doc(artboard);
  bad.syntax.string = 'teal';
  assert.throws(() => validateTheme(bad), /syntax\.string: "teal"/);
  delete bad.syntax;
  assert.throws(() => validateTheme(bad), /missing \[syntax\]/);
});

test('rendered tokens check out, and a bad colour in them is refused by name', () => {
  const t = validateTheme(doc(artboard));
  assert.deepEqual(checkTokens(JSON.parse(JSON.stringify(t))), t);
  assert.throws(() => checkTokens({ ...t, color: { ...t.color, paper: 'notacolor' } }), /color\.paper/);
});

test('the niri fragment sets the paper as background, frames windows 1 px in ink and the line colour, square, with no ring or shadow', () => {
  const kdl = renderNiri(artboard);
  assert.match(kdl, /background-color "#E4E6EA"/);
  assert.match(kdl, /focus-ring \{\s*off\s*\}/);
  assert.match(kdl, new RegExp(`border \\{\\s*on\\s*width 1\\s*active-color "#15171B"\\s*inactive-color "${artboard.color.line}"`));
  assert.match(kdl, /shadow \{\s*off\s*\}/);
  assert.match(kdl, /geometry-corner-radius 0/);
});

test('windows sit 56 px down and 32 px in, clear of the margins, with niri drawing their frames', () => {
  const kdl = renderNiri(artboard);
  assert.match(kdl, /struts \{\s*top 28\s*bottom 0\s*left 4\s*right 4\s*\}/);
  assert.match(kdl, /^prefer-no-csd$/m);
});

test('every animation runs on the spring, the window opening on damping 0.72 and stiffness 380', () => {
  const kdl = renderNiri(artboard);
  assert.match(kdl, /window-open \{\s*spring damping-ratio=0\.72 stiffness=380 epsilon=0\.0001/);
  assert.match(kdl, /window-close \{\s*duration-ms 160\s*curve "ease-out-quad"/);
  assert.match(kdl, /workspace-switch \{\s*spring damping-ratio=0\.85 stiffness=600/);
  assert.doesNotMatch(kdl, /slowdown/);
});

test('windows spring up from 96% and fade in, and shrink, sink and fade out', () => {
  const kdl = renderNiri(artboard);
  const shader = (name) => kdl.match(new RegExp(`${name} \\{[^}]*?custom-shader r"([^"]*)"`))?.[1];
  assert.match(shader('window-open'), /vec4 open_color[\s\S]*0\.96 \+ 0\.04 \* niri_progress[\s\S]*smoothstep\(0\.0, 0\.6, niri_clamped_progress\)/);
  assert.match(shader('window-close'), /vec4 close_color[\s\S]*1\.0 - 0\.04 \* p[\s\S]*\* \(1\.0 - smoothstep\(0\.0, 1\.0, p\)\)/);
});

test('every scheme renders the same niri fragment but for its colours', () => {
  const shape = (name) => renderNiri(loadScheme(name)).replace(/#[0-9A-Fa-f]{6}(80)?/g, '#');
  for (const name of SCHEMES) assert.equal(shape(name), shape('artboard'), name);
});

test('the backdrop between workspaces during a switch is the paper, not niri\'s grey', () => {
  for (const name of SCHEMES) {
    const t = loadScheme(name);
    assert.match(renderNiri(t), new RegExp(`overview \\{\\s*backdrop-color "${t.color.paper}"\\s*\\}`));
  }
});

test('niri tabs sit at the top in ink and the line colour, square', () => {
  const tabs = renderNiri(artboard).match(/^    tab-indicator \{\n([^]*?)\n    \}$/m)?.[1] ?? '';
  assert.match(tabs, /^\s+position "top"$/m);
  assert.match(tabs, /^\s+width 4$/m);
  assert.match(tabs, /^\s+corner-radius 0$/m);
  assert.match(tabs, /^\s+length total-proportion=0\.3$/m);
  assert.match(tabs, /^\s+active-color "#15171B"$/m);
  assert.match(tabs, new RegExp(`^\\s+inactive-color "${artboard.color.line}"$`, 'm'));
  assert.match(tabs, /^\s+hide-when-single-tab$/m);
  assert.match(tabs, /^\s+place-within-column$/m);
});

test('niri shows where a moved window lands in the accent at half strength', () => {
  assert.match(renderNiri(artboard), /^    insert-hint \{\n        color "#3D5AFE80"\n    \}$/m);
});

test('niri dresses the Alt+Tab switcher: the highlight takes the accent, danger for urgent, square', () => {
  const hl = renderNiri(gruvbox).match(/^recent-windows \{\n    highlight \{\n([^]*?)\n    \}\n\}$/m)?.[1] ?? '';
  assert.match(hl, new RegExp(`^        active-color "${gruvbox.color.accent}"$`, 'm'));
  assert.match(hl, new RegExp(`^        urgent-color "${gruvbox.color.danger}"$`, 'm'));
  assert.match(hl, /^        corner-radius 0$/m);
});

test('a tab position outside left, right, top and bottom is refused by name', () => {
  const bad = doc(artboard);
  bad.niri.tab_position = 'middle';
  assert.throws(() => validateTheme(bad), /niri\.tab_position: "middle"/);
});

test('the foot fragment carries the palette in its own mode section', () => {
  const ini = renderFoot(artboard);
  // A light scheme fills [colors-light] and starts in it, so foot tells apps the truth about light and dark.
  assert.match(ini, /^\[main\]\ninitial-color-theme=light\n\[colors-light\]$/m);
  assert.doesNotMatch(ini, /colors-dark/);
  assert.match(ini, /^background=FFFFFF$/m);
  assert.match(ini, /^foreground=15171B$/m);
});

test('foot\'s own chrome takes the scheme too: cursor, selection, URLs, labels, search', () => {
  const ini = renderFoot(gruvbox);
  assert.match(ini, /^initial-color-theme=dark\n\[colors-dark\]$/m);
  assert.match(ini, /^cursor=282828 83A598$/m);
  assert.match(ini, /^selection-background=83A598$/m);
  assert.match(ini, /^urls=83A598$/m);
  assert.match(ini, /^regular1=CC241D$/m);
});

test('the footclient overrides say what the fragment says, one per line', () => {
  const args = renderFootArgs(artboard).trim().split('\n');
  assert.equal(args[0], 'main.initial-color-theme=light');
  assert.ok(args.includes('colors-light.background=FFFFFF'));
  assert.ok(args.includes('colors-light.cursor=FFFFFF 3D5AFE'));
  assert.equal(args.length, renderFoot(artboard).split('\n').filter((l) => l.includes('=')).length);
});

test('foot accepts the home foot.ini with each scheme included', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dots-foot-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const home = readFileSync(new URL('../../home/dot_config/foot/foot.ini', import.meta.url), 'utf8');
  for (const name of SCHEMES) {
    writeFileSync(join(dir, 'theme.ini'), renderFoot(loadScheme(name)));
    writeFileSync(join(dir, 'foot.ini'), home.replace(/^include=.*$/m, `include=${join(dir, 'theme.ini')}`));
    execFileSync('foot', ['--check-config', '-c', join(dir, 'foot.ini')], { stdio: 'pipe' });
  }
});

test('the foot OSC string sets the 16 colours, cursor and selection, then foreground and background', () => {
  const osc = renderFootOsc(gruvbox);
  assert.ok(osc.startsWith('\x1b]4;0;#282828\x1b\\'));
  assert.ok(osc.includes('\x1b]12;#83A598\x1b\\\x1b]17;#83A598\x1b\\\x1b]19;#282828\x1b\\'));
  assert.ok(osc.endsWith('\x1b]10;#EBDBB2\x1b\\\x1b]11;#282828\x1b\\'));
});

test('ink reads at 4.5:1 or more on each surface', () => {
  for (const name of SCHEMES) {
    const t = loadScheme(name);
    assert.ok(contrast(t.color.ink, t.color.surface) >= 4.5, `${name}: ${contrast(t.color.ink, t.color.surface).toFixed(2)}`);
  }
});

test('contrast is the WCAG ratio, either way round', () => {
  assert.equal(contrast('#000000', '#FFFFFF'), 21);
  assert.equal(contrast('#FFFFFF', '#000000'), 21);
  assert.equal(contrast('#777777', '#777777'), 1);
});
