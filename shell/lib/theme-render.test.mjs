import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
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
