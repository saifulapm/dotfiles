import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { covered, doubled } from './comments.mjs';

// Untracked files count, so a file is checked before its commit.
const root = new URL('../..', import.meta.url).pathname;
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' }).split('\n').filter(covered);

test('no file has two comment lines in a row', () => {
  const found = files.flatMap((f) => doubled(f, readFileSync(join(root, f), 'utf8')).map((n) => `${f}:${n}`));
  assert.deepEqual(found, []);
});

// An implementer commits on its own branch, and the wave suite was the first to see its two comment lines three times, so the commit itself refuses them.
test('dots-pre-commit refuses a staged file with two comment lines in a row, and passes one with none', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'pre-commit-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  // An empty global config, so the machine's hooks and settings stay out of the fixture repo.
  const env = { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' };
  const git = (...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8', env });
  git('init', '-q');
  const hook = () => spawnSync(join(root, 'bin/dots-pre-commit'), [], { cwd: dir, encoding: 'utf8', env });
  writeFileSync(join(dir, 'a.sh'), '#!/bin/sh\n# one line\necho a\n');
  git('add', 'a.sh');
  assert.equal(hook().status, 0, hook().stderr);
  // The staged text is what counts, so a fix left unstaged still fails.
  writeFileSync(join(dir, 'a.sh'), '#!/bin/sh\n# one line\n# and another\necho a\n');
  git('add', 'a.sh');
  writeFileSync(join(dir, 'a.sh'), '#!/bin/sh\n# one line\necho a\n');
  const r = hook();
  assert.equal(r.status, 1);
  assert.match(r.stderr, /a\.sh:3/);
});
