// zathurarc keeps v1's behaviour and includes the fragment dots theme renders, by an absolute path, since a relative one resolves beside the config file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;

test('zathurarc keeps v1\'s behaviour and includes the rendered theme fragment', () => {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-zathura-')));
  writeFileSync(join(home, 'chezmoi.toml'), '[data]\nmachine = "test"\n');
  const input = readFileSync(join(repo, 'home/dot_config/zathura/zathurarc.tmpl'), 'utf8');
  const r = spawnSync('chezmoi', ['--config', join(home, 'chezmoi.toml'), '--source', repo, 'execute-template'], { input, encoding: 'utf8', env: { PATH: process.env.PATH, HOME: home } });
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.split('\n').filter((l) => l && !l.startsWith('#'));
  for (const l of ['set selection-clipboard clipboard', 'set adjust-open best-fit', 'set window-title-basename true', 'set statusbar-basename true']) assert.ok(lines.includes(l), l);
  assert.equal(lines.at(-1), `include ${home}/.local/state/dots/theme-out/zathura`);
});
