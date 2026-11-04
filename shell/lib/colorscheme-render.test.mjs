import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, writeFileSync, rmSync, cpSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../..', import.meta.url).pathname;
const cli = new URL('./colorscheme-render.mjs', import.meta.url).pathname;
const themeCli = new URL('./theme-render.mjs', import.meta.url).pathname;
const scratch = (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dots-scheme-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
};
const files = (dir) => readdirSync(dir, { recursive: true }).sort();

test('a colorscheme renders every output the theme render made', (t) => {
  const a = scratch(t);
  const b = scratch(t);
  execFileSync('node', [themeCli, 'artboard'], { env: { ...process.env, XDG_STATE_HOME: a } });
  execFileSync('node', [cli, 'artboard'], { env: { ...process.env, XDG_STATE_HOME: b } });
  assert.deepEqual(files(join(b, 'dots/theme-out')), files(join(a, 'dots/theme-out')));
});

test('the shell tokens name the one design and the scheme\'s light or dark', (t) => {
  const state = scratch(t);
  execFileSync('node', [cli, 'artboard'], { env: { ...process.env, XDG_STATE_HOME: state } });
  const out = join(state, 'dots/theme-out');
  const shell = JSON.parse(readFileSync(join(out, 'shell.json'), 'utf8'));
  assert.equal(shell.name, 'artboard');
  assert.equal(shell.mode, 'light');
  assert.deepEqual(shell.primitive, { paper: 'dots', frame: 'ink', shadow: 'none', corner: 'square', motion: 'spring' });
  assert.equal(shell.type.voice, 'plain');
  assert.equal(shell.color.paper, '#E4E6EA');
  assert.equal(shell.color.surface, '#FFFFFF');
  assert.match(readFileSync(join(out, 'foot.ini'), 'utf8'), /^background=FFFFFF$/m);
  const config = join(state, 'config.kdl');
  writeFileSync(config, `include "${join(out, 'niri.kdl')}"\n`);
  execFileSync('niri', ['validate', '-c', config], { stdio: 'pipe' });
});

test('themes.json lists every valid scheme, artboard first, and skips a broken one', (t) => {
  const root = scratch(t);
  for (const d of ['shell/lib', 'shell/newtab', 'colorschemes']) cpSync(join(repo, d), join(root, d), { recursive: true });
  writeFileSync(join(root, 'colorschemes/aaa-broken.toml'), '[meta]\nname = "aaa-broken"\n');
  const state = join(root, 'state');
  execFileSync('node', [join(root, 'shell/lib/colorscheme-render.mjs'), 'artboard'], { env: { ...process.env, XDG_STATE_HOME: state } });
  const list = JSON.parse(readFileSync(join(state, 'dots/theme-out/themes.json'), 'utf8'));
  assert.equal(list[0].name, 'artboard');
  assert.equal(list[0].title, 'Artboard');
  assert.ok(!list.some((s) => s.name === 'aaa-broken'));
  assert.deepEqual(list.map((s) => s.name).sort(), readdirSync(join(repo, 'colorschemes')).filter((f) => f.endsWith('.toml')).map((f) => f.slice(0, -5)).sort());
});

test('an unknown name exits 1 with no such colorscheme and writes nothing', (t) => {
  const state = scratch(t);
  for (const name of ['nope', 'frost', '../themes/paper']) {
    const r = spawnSync('node', [cli, name], { env: { ...process.env, XDG_STATE_HOME: state }, encoding: 'utf8' });
    assert.equal(r.status, 1, name);
    assert.equal(r.stderr, `colorscheme ${name}: no such colorscheme\n`);
  }
  assert.deepEqual(readdirSync(state), []);
});

test('a file the check refuses exits 1 with its reason and writes nothing', (t) => {
  const root = scratch(t);
  for (const d of ['shell/lib', 'shell/newtab', 'colorschemes']) cpSync(join(repo, d), join(root, d), { recursive: true });
  const art = readFileSync(join(repo, 'colorschemes/artboard.toml'), 'utf8');
  writeFileSync(join(root, 'colorschemes/faint.toml'), art.replace('name = "artboard"', 'name = "faint"').replace('ink = "#15171B"', 'ink = "#9AA0A6"'));
  writeFileSync(join(root, 'colorschemes/shaped.toml'), art + '\n[niri]\ngaps = 4\n');
  const state = join(root, 'state');
  mkdirSync(state);
  const render = (name) => spawnSync('node', [join(root, 'shell/lib/colorscheme-render.mjs'), name], { env: { ...process.env, XDG_STATE_HOME: state }, encoding: 'utf8' });
  const faint = render('faint');
  assert.equal(faint.status, 1);
  assert.match(faint.stderr, /^colorscheme faint: contrast of ink on surface is [\d.]+:1, under 4\.5:1\n$/);
  const shaped = render('shaped');
  assert.equal(shaped.status, 1);
  assert.match(shaped.stderr, /^colorscheme shaped: \[niri\]/);
  assert.deepEqual(readdirSync(state), []);
});

const saved = (t, content) => {
  const state = scratch(t);
  if (content !== null) {
    mkdirSync(join(state, 'dots'));
    writeFileSync(join(state, 'dots/theme'), content);
  }
  const r = spawnSync('node', [cli, '--saved'], { env: { ...process.env, XDG_STATE_HOME: state }, encoding: 'utf8' });
  const shell = JSON.parse(readFileSync(join(state, 'dots/theme-out/shell.json'), 'utf8'));
  return { r, shell, file: readFileSync(join(state, 'dots/theme'), 'utf8') };
};

test('--saved turns an old theme name into artboard and saves it', (t) => {
  const { r, shell, file } = saved(t, 'frost\n');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(file, 'artboard\n');
  assert.equal(shell.name, 'artboard');
});

test('--saved with no saved file or an empty one renders and saves artboard', (t) => {
  for (const content of [null, '']) {
    const { r, shell, file } = saved(t, content);
    assert.equal(r.status, 0, r.stderr);
    assert.equal(file, 'artboard\n');
    assert.equal(shell.name, 'artboard');
  }
});

test('--saved renders a saved colorscheme and leaves the file as it was', (t) => {
  const { r, shell, file } = saved(t, 'artboard');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(file, 'artboard');
  assert.equal(shell.name, 'artboard');
});
