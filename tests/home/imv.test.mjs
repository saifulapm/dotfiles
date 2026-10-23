// imv's config is a link to the one dots theme renders, since imv has no include.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;

test('~/.config/imv/config links to the rendered imv.conf', () => {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-imv-')));
  writeFileSync(join(home, 'chezmoi.toml'), '[data]\nmachine = "test"\n');
  const input = readFileSync(join(repo, 'home/dot_config/imv/symlink_config.tmpl'), 'utf8');
  const r = spawnSync('chezmoi', ['--config', join(home, 'chezmoi.toml'), '--source', repo, 'execute-template'], { input, encoding: 'utf8', env: { PATH: process.env.PATH, HOME: home } });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), `${home}/.local/state/dots/theme-out/imv.conf`);
});
