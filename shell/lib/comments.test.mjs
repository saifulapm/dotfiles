import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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

// The shell/lib lint tests went red only in the wave suite five times (m24, m28, m61, m62, m95), so a commit touching shell or tests runs them.
test('dots-pre-commit runs the qml-js and fixture-git lint tests when a staged file is under shell or tests, and not otherwise', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'pre-commit-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' };
  const git = (...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8', env });
  git('init', '-q');
  const hook = () => spawnSync(join(root, 'bin/dots-pre-commit'), [], { cwd: dir, encoding: 'utf8', env });
  mkdirSync(join(dir, 'shell/lib'), { recursive: true });
  mkdirSync(join(dir, 'tests'));
  const red = "import { test } from 'node:test';\nimport assert from 'node:assert/strict';\ntest('lint', () => assert.fail('NAME went red'));\n";
  writeFileSync(join(dir, 'shell/lib/qml-js.test.mjs'), red.replace('NAME', 'qml-js'));
  writeFileSync(join(dir, 'shell/lib/fixture-git.test.mjs'), red.replace('NAME', 'fixture-git'));
  writeFileSync(join(dir, 'a.sh'), '#!/bin/sh\necho a\n');
  git('add', 'a.sh');
  assert.equal(hook().status, 0, hook().stderr);
  writeFileSync(join(dir, 'tests/b.mjs'), 'export const b = 1;\n');
  git('add', 'tests/b.mjs');
  const r = hook();
  assert.equal(r.status, 1);
  assert.match(r.stderr, /qml-js went red/);
  assert.match(r.stderr, /fixture-git went red/);
  writeFileSync(join(dir, 'shell/lib/qml-js.test.mjs'), red.replace("assert.fail('NAME went red')", 'assert.ok(true)'));
  writeFileSync(join(dir, 'shell/lib/fixture-git.test.mjs'), red.replace("assert.fail('NAME went red')", 'assert.ok(true)'));
  assert.equal(hook().status, 0, hook().stderr);
});

test('dots-pre-commit runs the one-design word scan when a staged file is under shell, bin or tests', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'pre-commit-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const env = { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' };
  const git = (...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8', env });
  git('init', '-q');
  const hook = () => spawnSync(join(root, 'bin/dots-pre-commit'), [], { cwd: dir, encoding: 'utf8', env });
  for (const d of ['shell/lib', 'bin']) mkdirSync(join(dir, d), { recursive: true });
  writeFileSync(join(dir, 'shell/lib/one-design.test.mjs'), "import { test } from 'node:test';\nimport assert from 'node:assert/strict';\ntest('scan', () => assert.fail('one-design went red'));\n");
  writeFileSync(join(dir, 'a.md'), 'a\n');
  git('add', 'a.md');
  assert.equal(hook().status, 0, hook().stderr);
  writeFileSync(join(dir, 'bin/tool'), '#!/bin/sh\necho a\n');
  git('add', 'bin/tool');
  const r = hook();
  assert.equal(r.status, 1);
  assert.match(r.stderr, /one-design went red/);
});
