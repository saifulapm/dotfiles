import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, writeFileSync, rmSync, cpSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const cli = new URL('./theme-render.mjs', import.meta.url).pathname;

test('renders every fragment into XDG_STATE_HOME/dots/theme-out', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-theme-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  execFileSync('node', [cli, 'paper'], { env: { ...process.env, XDG_STATE_HOME: state } });
  const out = join(state, 'dots/theme-out');
  const shell = JSON.parse(readFileSync(join(out, 'shell.json'), 'utf8'));
  assert.equal(shell.name, 'paper');
  assert.equal(shell.color.paper, '#F1E9D8');
  assert.match(readFileSync(join(out, 'foot.ini'), 'utf8'), /^background=FAF6EC$/m);
  const config = join(state, 'config.kdl');
  writeFileSync(config, `include "${join(out, 'niri.kdl')}"\n`);
  execFileSync('niri', ['validate', '-c', config], { stdio: 'pipe' });
});

test('renders the app fragments and no kitty file', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-theme-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  execFileSync('node', [cli, 'blueprint'], { env: { ...process.env, XDG_STATE_HOME: state } });
  const names = readdirSync(join(state, 'dots/theme-out'));
  for (const f of ['tmux.conf', 'dots.kak', 'helix.toml', 'yazi-theme.toml', 'colors.fish', 'gtk.css', 'gtk-settings.ini', 'chromium.json']) {
    assert.ok(names.includes(f), f);
  }
  assert.deepEqual(names.filter((n) => /kitty/i.test(n)), []);
});

test('an unknown theme exits non-zero and names it', () => {
  assert.throws(
    () => execFileSync('node', [cli, 'nope'], { stdio: 'pipe' }),
    (e) => /theme nope/.test(e.stderr.toString()),
  );
});

test('every theme renders a niri fragment niri accepts', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-theme-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  for (const name of ['paper', 'artboard', 'blueprint']) {
    execFileSync('node', [cli, name], { env: { ...process.env, XDG_STATE_HOME: state } });
    const config = join(state, 'config.kdl');
    writeFileSync(config, `include "${join(state, 'dots/theme-out/niri.kdl')}"\n`);
    execFileSync('niri', ['validate', '-c', config], { stdio: 'pipe' });
  }
});

test('themes.json lists every valid theme, paper first, and skips a broken one', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'dots-themes-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const repo = new URL('../..', import.meta.url).pathname;
  cpSync(join(repo, 'shell/lib'), join(root, 'shell/lib'), { recursive: true });
  cpSync(join(repo, 'themes'), join(root, 'themes'), { recursive: true });
  mkdirSync(join(root, 'themes/broken'));
  writeFileSync(join(root, 'themes/broken/theme.toml'), '[meta]\nname = "broken"\nmode = "dim"\n');
  const state = join(root, 'state');
  execFileSync('node', [join(root, 'shell/lib/theme-render.mjs'), 'paper'], { env: { ...process.env, XDG_STATE_HOME: state } });
  const themes = JSON.parse(readFileSync(join(state, 'dots/theme-out/themes.json'), 'utf8'));
  assert.deepEqual(themes.map((x) => x.name), ['paper', 'artboard', 'blueprint']);
  assert.deepEqual(Object.keys(themes[2]), ['name', 'mode', 'color', 'syntax', 'primitive', 'paper', 'type', 'niri']);
  assert.equal(themes[2].color.paper, '#0C1A2E');
  assert.equal(themes[2].primitive.frame, 'glow');
  assert.equal(themes[1].paper.dot, '#B4BAC4');
  assert.equal(themes[2].paper.minor, 16);
  assert.equal(themes[2].type.voice, 'bracket');
  assert.equal(themes[1].niri.ring_color, '#3D5AFE');
  assert.equal(themes[0].niri.border_inactive, '#575653');
});
