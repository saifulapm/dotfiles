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

test('every theme carries its code colours, each #RRGGBB', () => {
  assert.equal(validateTheme(paper).syntax.keyword, '#66800B');
  const bad = structuredClone(paper);
  bad.syntax.string = 'teal';
  assert.throws(() => validateTheme(bad), /syntax\.string: "teal"/);
  delete bad.syntax;
  assert.throws(() => validateTheme(bad), /missing \[syntax\]/);
});

test('the niri fragment sets the paper as background and the ink frame', () => {
  const kdl = renderNiri(validateTheme(paper));
  assert.match(kdl, /background-color "#F1E9D8"/);
  assert.match(kdl, /focus-ring \{\s*off\s*\}/);
  assert.match(kdl, /border \{\s*on\s*width 1\s*active-color "#1C1915"/);
  assert.match(kdl, /shadow \{\s*on\s*softness 0\s*spread 0\s*offset x=3 y=3\s*color "#1C1915"/);
  assert.match(kdl, /geometry-corner-radius 0/);
});

test('windows sit 56 px down and 32 px in, under the margins\' 41 px zone, with niri drawing their frames', () => {
  const kdl = renderNiri(validateTheme(paper));
  assert.match(kdl, /struts \{\s*top -9\s*bottom 4\s*left 8\s*right 8\s*\}/);
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

test('each theme\'s fragment times every animation from its motion', () => {
  const block = (kdl, name) => kdl.match(new RegExp(`\\n    ${name} \\{\\n([\\s\\S]*?)\\n    \\}`))?.[1].split('custom-shader')[0].trim().split(/\s*\n\s*/);
  const paper = renderNiri(load('paper'));
  assert.deepEqual(block(paper, 'workspace-switch'), ['spring damping-ratio=1.0 stiffness=1200 epsilon=0.0001']);
  assert.deepEqual(block(paper, 'window-close'), ['duration-ms 100', 'curve "ease-out-quad"']);
  const blueprint = renderNiri(load('blueprint'));
  assert.deepEqual(block(blueprint, 'window-movement'), ['duration-ms 150', 'curve "linear"']);
  assert.deepEqual(block(blueprint, 'exit-confirmation-open-close'), ['duration-ms 150', 'curve "linear"']);
  const artboard = renderNiri(load('artboard'));
  assert.deepEqual(block(artboard, 'config-notification-open-close'), ['spring damping-ratio=0.6 stiffness=1000 epsilon=0.0001']);
  assert.deepEqual(block(artboard, 'screenshot-ui-open'), ['duration-ms 200', 'curve "ease-out-cubic"']);
  for (const kdl of [paper, blueprint, artboard]) {
    for (const name of ['window-open', 'window-close', 'workspace-switch', 'horizontal-view-movement', 'window-movement', 'window-resize',
      'overview-open-close', 'screenshot-ui-open', 'config-notification-open-close', 'exit-confirmation-open-close']) {
      assert.ok(block(kdl, name), `${name} is set`);
    }
  }
});

test('a motion outside the three boards keeps one open and close curve and leaves the rest to niri', () => {
  const t = load('paper');
  t.primitive.motion = 'ease';
  const kdl = renderNiri(t);
  assert.match(kdl, /window-open \{\s*duration-ms 200\s*curve "ease-out-cubic"\s*\}/);
  assert.doesNotMatch(kdl, /workspace-switch|window-movement/);
});

test('no rendered fragment slows niri\'s animations; slowdown belongs to the nested test config', () => {
  for (const name of ['paper', 'artboard', 'blueprint']) assert.doesNotMatch(renderNiri(load(name)), /slowdown/);
});

test('Blueprint opens and closes with its own shaders, its pen baked in as its accent', () => {
  const kdl = renderNiri(load('blueprint'));
  const shader = (name) => kdl.match(new RegExp(`${name} \\{[^}]*?custom-shader r"([^"]*)"`))?.[1];
  assert.match(shader('window-open'), /vec4 open_color\(vec3 coords_geo, vec3 size_geo\)/);
  assert.match(shader('window-close'), /vec4 close_color\(vec3 coords_geo, vec3 size_geo\)/);
  for (const glsl of [shader('window-open'), shader('window-close')]) assert.match(glsl, /vec4\(0\.498, 0\.890, 0\.941, 1\.0\)/);
});

test('Paper drops its windows in whole and lifts them out, 8 px either way, with no fade', () => {
  const kdl = renderNiri(load('paper'));
  const shader = (name) => kdl.match(new RegExp(`${name} \\{[^}]*?custom-shader r"([^"]*)"`))?.[1];
  assert.match(shader('window-open'), /vec4 open_color[\s\S]*8\.0 \* \(1\.0 - p\)/);
  assert.match(shader('window-close'), /vec4 close_color[\s\S]*8\.0 \* p/);
  for (const glsl of [shader('window-open'), shader('window-close')]) assert.doesNotMatch(glsl, /\* p;|\* \(1\.0 - p\);/);
});

test('Artboard springs its windows up from 96% and fades them in, and shrinks, sinks and fades them out', () => {
  const kdl = renderNiri(load('artboard'));
  const shader = (name) => kdl.match(new RegExp(`${name} \\{[^}]*?custom-shader r"([^"]*)"`))?.[1];
  assert.match(shader('window-open'), /vec4 open_color[\s\S]*0\.96 \+ 0\.04 \* niri_progress[\s\S]*smoothstep\(0\.0, 0\.6, niri_clamped_progress\)/);
  assert.match(shader('window-close'), /vec4 close_color[\s\S]*1\.0 - 0\.04 \* p[\s\S]*\* \(1\.0 - smoothstep\(0\.0, 1\.0, p\)\)/);
});

// One physical pixel, so a 1 px line stays one row on the 1.25 panel instead of flickering between one and two.
test('a shader measures one physical pixel from niri_scale', () => {
  for (const name of ['paper', 'blueprint']) {
    const kdl = renderNiri(load(name));
    assert.match(kdl, /float dots_px\(\) \{\n\s*return niri_scale > 0\.5 \? 1\.0 \/ niri_scale : 1\.0;\n\s*\}/, name);
  }
});

test('Paper\'s 8 px drop and lift move in whole physical pixels, so its text stays sharp', () => {
  const kdl = renderNiri(load('paper'));
  const shader = (name) => kdl.match(new RegExp(`${name} \\{[^}]*?custom-shader r"([^"]*)"`))?.[1];
  assert.match(shader('window-open'), /floor\(8\.0 \* \(1\.0 - p\) \/ w \+ 0\.5\) \* w/);
  assert.match(shader('window-close'), /floor\(8\.0 \* p \/ w \+ 0\.5\) \* w/);
});

// The glow is niri's shadow, drawn into niri_tex below the window too, so a scan that stopped at the window's edge popped it on at the end.
test('Blueprint\'s scan runs past the window by its glow\'s reach, its pen one physical pixel wide with a bright tip', () => {
  const kdl = renderNiri(load('blueprint'));
  const shader = (name) => kdl.match(new RegExp(`${name} \\{[^}]*?custom-shader r"([^"]*)"`))?.[1];
  for (const glsl of [shader('window-open'), shader('window-close')]) {
    assert.match(glsl, /float reach = 18\.0;/);
    assert.match(glsl, /\* \(size_geo\.y \+ 2\.0 \* reach\)/);
    assert.match(glsl, /dots_outline\(px, size_geo\.xy, w\)/);
    assert.match(glsl, /px\.y < scan \+ w\)/);
  }
  assert.match(shader('window-open'), /mix\(vec4\(0\.498, 0\.890, 0\.941, 1\.0\), vec4\(1\.0\), 0\.7\)/);
});

test('a theme with no shadow scans no further than its window', () => {
  const t = load('blueprint');
  delete t.niri.shadow_color;
  assert.match(renderNiri(t), /float reach = 0\.0;/);
});

test('a motion no board draws keeps niri\'s own open and close', () => {
  const t = load('blueprint');
  t.primitive.motion = 'typewriter';
  assert.doesNotMatch(renderNiri(t), /custom-shader/);
});

test('the backdrop between workspaces during a switch is the theme\'s paper, not niri\'s grey', () => {
  for (const name of ['paper', 'artboard', 'blueprint']) {
    const t = load(name);
    assert.match(renderNiri(t), new RegExp(`overview \\{\\s*backdrop-color "${t.color.paper}"\\s*\\}`));
  }
});

test('a theme without shadow keys gets no shadow', () => {
  const t = load('paper');
  delete t.niri.shadow_color;
  assert.match(renderNiri(t), /shadow \{\s*off\s*\}/);
});

test('the foot OSC string sets the 16 colours, cursor and selection, then foreground and background', () => {
  const osc = renderFootOsc(load('blueprint'));
  assert.ok(osc.startsWith('\x1b]4;0;#2E5A72\x1b\\'));
  assert.ok(osc.includes('\x1b]4;15;#FFFFFF\x1b\\'));
  assert.ok(osc.includes('\x1b]12;#7FE3F0\x1b\\\x1b]17;#7FE3F0\x1b\\\x1b]19;#0A1526\x1b\\'));
  assert.ok(osc.endsWith('\x1b]10;#D6F4F8\x1b\\\x1b]11;#0A1526\x1b\\'));
});

const tabs = (name) => renderNiri(load(name)).match(/^    tab-indicator \{\n([^]*?)\n    \}$/m)?.[1] ?? '';

test('each theme draws niri tabs in its own language: Paper index tabs, Artboard pills, Blueprint a dimension line', () => {
  const paper = tabs('paper');
  assert.match(paper, /^\s+position "top"$/m);
  assert.match(paper, /^\s+width 5$/m);
  assert.match(paper, /^\s+corner-radius 0$/m);
  // niri reads total-proportion only as a float, so 1.0 keeps its point.
  assert.match(paper, /^\s+length total-proportion=1\.0$/m);
  assert.match(paper, /^\s+active-color "#1C1915"$/m);
  assert.match(paper, /^\s+inactive-color "#575653"$/m);
  const artboard = tabs('artboard');
  assert.match(artboard, /^\s+length total-proportion=0\.3$/m);
  assert.match(artboard, /^\s+corner-radius 2$/m);
  assert.match(artboard, /^\s+active-color "#3D5AFE"$/m);
  const blueprint = tabs('blueprint');
  assert.match(blueprint, /^\s+position "left"$/m);
  assert.match(blueprint, /^\s+width 2$/m);
  assert.match(blueprint, /^\s+active-color "#7FE3F0"$/m);
  assert.match(blueprint, /^\s+inactive-color "#2E5A72"$/m);
  for (const t of [paper, artboard, blueprint]) {
    assert.match(t, /^\s+hide-when-single-tab$/m);
    assert.match(t, /^\s+place-within-column$/m);
  }
});

test('niri shows where a moved window lands in the theme accent at half strength', () => {
  assert.match(renderNiri(load('blueprint')), /^    insert-hint \{\n        color "#7FE3F080"\n    \}$/m);
});

test('niri dresses the Alt+Tab switcher: the highlight takes the accent, danger for urgent, and the corner primitive', () => {
  for (const name of ['paper', 'blueprint', 'artboard']) {
    const t = load(name);
    const hl = renderNiri(t).match(/^recent-windows \{\n    highlight \{\n([^]*?)\n    \}\n\}$/m)?.[1] ?? '';
    assert.match(hl, new RegExp(`^        active-color "${t.color.accent}"$`, 'm'), name);
    assert.match(hl, new RegExp(`^        urgent-color "${t.color.danger}"$`, 'm'), name);
    assert.match(hl, new RegExp(`^        corner-radius ${t.primitive.corner === 'round' ? 14 : 0}$`, 'm'), name);
  }
});

test('a tab position outside left, right, top and bottom is refused by name', () => {
  const bad = structuredClone(paper);
  bad.niri.tab_position = 'middle';
  assert.throws(() => validateTheme(bad), /niri\.tab_position: "middle"/);
});
