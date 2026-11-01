import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseToml } from './toml.mjs';
import { validateTheme, renderNiri, renderFoot } from './theme.mjs';
import { renderZathura, renderChromiumTheme, renderGtkSettings } from './apps.mjs';

const render = new URL('./theme-render.mjs', import.meta.url).pathname;
const dots = new URL('../../bin/dots', import.meta.url).pathname;
const load = (n) => parseToml(readFileSync(new URL(`../../themes/${n}/theme.toml`, import.meta.url), 'utf8'));
const hifi = () => validateTheme(load('hi-fi'));
const sha = (b) => createHash('sha256').update(b).digest('hex');

// Every fragment the three older themes rendered before Hi-Fi, by hash; the copies of shell/newtab's own files and the card list change on purpose.
const GOLDEN = JSON.parse(readFileSync(new URL('./testdata/theme-goldens.json', import.meta.url), 'utf8'));

function renderInto(state, name) {
  const r = spawnSync(process.execPath, [render, name], { env: Object.assign({}, process.env, { XDG_STATE_HOME: state }), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return join(state, 'dots/theme-out');
}

function files(dir, rel = '') {
  return readdirSync(join(dir, rel)).flatMap((f) => (statSync(join(dir, rel, f)).isDirectory() ? files(dir, join(rel, f)) : [join(rel, f)]));
}

test('Paper, Artboard and Blueprint render every fragment as before, and shell.json differs only by a glass equal to surface', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-golden-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  for (const name of ['paper', 'artboard', 'blueprint']) {
    const out = renderInto(join(state, name), name);
    const got = {};
    for (const f of files(out)) {
      if (!(f in GOLDEN[name])) continue;
      let text = readFileSync(join(out, f), 'utf8');
      if (f === 'shell.json') {
        const doc = JSON.parse(text);
        assert.equal(doc.color.glass, doc.color.surface, `${name}: glass defaults to surface`);
        delete doc.color.glass;
        text = JSON.stringify(doc, null, 2) + '\n';
      }
      got[f] = sha(text);
    }
    assert.deepEqual(got, GOLDEN[name], `${name}: a fragment changed`);
  }
});

test('Hi-Fi validates with its brushed paper, dial motion, engraved voice and glass', () => {
  const t = hifi();
  assert.equal(t.name, 'hi-fi');
  assert.equal(t.mode, 'dark');
  assert.deepEqual([t.primitive.paper, t.primitive.motion, t.type.voice], ['brushed', 'dial', 'engraved']);
  assert.equal(t.color.glass, '#141617');
  assert.equal(t.niri.border_active, '#FABD2F');
});

test('glass is optional and checked like any colour; a theme without it gets its surface', () => {
  const bad = load('hi-fi');
  bad.color.glass = 'blue';
  assert.throws(() => validateTheme(bad), /color\.glass: "blue" is not #RRGGBB/);
  const blueprint = validateTheme(load('blueprint'));
  assert.equal(blueprint.color.glass, blueprint.color.surface);
  const border = load('hi-fi');
  border.niri.border_active = 'amber';
  assert.throws(() => validateTheme(border), /niri\.border_active: "amber"/);
});

test('Hi-Fi frames the focused window in a 1 px amber border with an amber glow, the rest in #3C3836', () => {
  const kdl = renderNiri(hifi());
  assert.match(kdl, /border \{\s*on\s*width 1\s*active-color "#FABD2F"\s*inactive-color "#3C3836"/);
  assert.match(kdl, /shadow \{\s*on\s*softness 24\s*spread 0\s*offset x=0 y=0\s*color "#FABD2F38"\s*inactive-color "#00000000"/);
  assert.match(kdl, /gaps 24/);
  assert.match(kdl, /geometry-corner-radius 0/);
  assert.match(kdl, /tab-indicator \{[\s\S]*?active-color "#FABD2F"/);
});

test('Hi-Fi times its camera like a tuning dial, in curves niri accepts', () => {
  const block = (kdl, name) => kdl.match(new RegExp(`\\n    ${name} \\{\\n([\\s\\S]*?)\\n    \\}`))?.[1].split('custom-shader')[0].trim().split(/\s*\n\s*/);
  const kdl = renderNiri(hifi());
  // niri 26.04 knows no ease-in-out-cubic or ease-in by name, so they are its cubic-bezier.
  const inOut = (ms) => [`duration-ms ${ms}`, 'curve "cubic-bezier" 0.65 0 0.35 1'];
  assert.deepEqual(block(kdl, 'workspace-switch'), inOut(260));
  assert.deepEqual(block(kdl, 'horizontal-view-movement'), inOut(260));
  assert.deepEqual(block(kdl, 'overview-open-close'), inOut(240));
  assert.deepEqual(block(kdl, 'window-movement'), ['duration-ms 200', 'curve "ease-out-cubic"']);
  assert.deepEqual(block(kdl, 'window-resize'), ['duration-ms 200', 'curve "ease-out-cubic"']);
  assert.deepEqual(block(kdl, 'window-open'), ['duration-ms 220', 'curve "linear"']);
  assert.deepEqual(block(kdl, 'window-close'), ['duration-ms 140', 'curve "linear"']);
  for (const name of ['screenshot-ui-open', 'config-notification-open-close', 'exit-confirmation-open-close']) {
    assert.deepEqual(block(kdl, name), ['duration-ms 160', 'curve "ease-out-cubic"']);
  }
});

test('Hi-Fi warms its windows up in 220 ms and powers them off in 140 ms, its amber baked in', () => {
  const kdl = renderNiri(hifi());
  const shader = (name, ms) => kdl.match(new RegExp(`${name} \\{\\s*duration-ms ${ms}[^}]*?custom-shader r"([^"]*)"`))?.[1];
  const open = shader('window-open', 220);
  const close = shader('window-close', 140);
  assert.match(open, /vec4 open_color\(vec3 coords_geo, vec3 size_geo\)/);
  assert.match(close, /vec4 close_color\(vec3 coords_geo, vec3 size_geo\)/);
  assert.match(close, /float w = dots_px\(\);/);
  assert.match(close, /vec4\(0\.980, 0\.741, 0\.184, 1\.0\)/);
  // niri's progress is linear time, so the glow's 60 ms and 40 ms windows are those fractions of it, and the shaders ease the window.
  assert.match(open, /clamp\(\(p - 160\.0 \/ 220\.0\) \/ \(60\.0 \/ 220\.0\), 0\.0, 1\.0\)/);
  assert.match(open, /color \* p \* p \* p/);
  assert.match(close, /clamp\(p \/ \(40\.0 \/ 140\.0\), 0\.0, 1\.0\)/);
  // The outline fades over the last 10%, so niri's last frame is the paper alone.
  assert.match(close, /0\.3 \* \(1\.0 - smoothstep\(0\.9, 1\.0, p\)\)/);
});

test('niri accepts Hi-Fi\'s fragment', (t) => {
  if (spawnSync('niri', ['--version']).status !== 0) return t.skip('no niri here');
  const dir = mkdtempSync(join(tmpdir(), 'dots-hifi-niri-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, 'niri.kdl'), renderNiri(hifi()));
  const r = spawnSync('niri', ['validate', '-c', join(dir, 'niri.kdl')], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
});

test('Hi-Fi\'s apps are Gruvbox Dark: foot, zathura, Chromium and GTK', () => {
  const t = hifi();
  const foot = renderFoot(t);
  assert.match(foot, /\[colors-dark\][\s\S]*regular1=CC241D/);
  assert.match(foot, /\[colors-dark\][\s\S]*background=282828/);
  assert.match(foot, /initial-color-theme=dark/);
  const zathura = renderZathura(t);
  assert.match(zathura, /set recolor true/);
  assert.match(zathura, /set recolor-keephue true/);
  assert.match(renderZathura(validateTheme(load('paper'))), /set recolor false/);
  const chrome = JSON.parse(renderChromiumTheme(t)).theme.colors;
  assert.deepEqual([chrome.frame, chrome.toolbar], [[29, 32, 33], [40, 40, 40]]);
  assert.match(renderGtkSettings(t), /gtk-application-prefer-dark-theme=true/);
});

test('dots theme hi-fi switches, sets GTK dark, and Paper after it sets light again', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-hifi-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const bin = join(state, 'bin');
  mkdirSync(bin);
  const log = join(state, 'gsettings.log');
  writeFileSync(join(bin, 'gsettings'), `#!/bin/bash\necho "$*" >>${log}\n`, { mode: 0o755 });
  const env = Object.assign({}, process.env, {
    PATH: `${bin}:${process.env.PATH}`, XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${state}/no-bus`,
    TMUX_TMPDIR: state, XDG_RUNTIME_DIR: state, DOTS_AGENT_HOME: `${state}/agents`,
  });
  delete env.TMUX;
  const r = spawnSync(dots, ['theme', 'hi-fi'], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readFileSync(join(state, 'dots/theme'), 'utf8').trim(), 'hi-fi');
  assert.match(readFileSync(log, 'utf8'), /color-scheme prefer-dark/);
  assert.equal(spawnSync(dots, ['theme', 'paper'], { env }).status, 0);
  assert.match(readFileSync(log, 'utf8').trim().split('\n').filter((l) => l.includes('color-scheme')).pop(), /prefer-light/);
  assert.match(readFileSync(join(state, 'dots/theme-out/zathura'), 'utf8'), /set recolor false/);
});
