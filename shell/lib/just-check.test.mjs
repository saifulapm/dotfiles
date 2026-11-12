import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// just check is the project's verify command, so its exit code is pinned here: a stand-in runner plays each suite, red when its name is in RED.
const repo = new URL('../..', import.meta.url).pathname;

function check(t, red) {
  const dir = mkdtempSync(join(tmpdir(), 'just-check-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const runner = join(dir, 'runner');
  const log = join(dir, 'log');
  writeFileSync(runner, `#!/bin/sh\necho "$1" >>${log}\ncase " $RED " in *" $1 "*) exit 1 ;; esac\nexit 0\n`, { mode: 0o755 });
  const r = spawnSync('just', ['--justfile', join(repo, 'justfile'), '--working-directory', repo, '--set', 'runner', runner, 'check'], {
    encoding: 'utf8',
    env: { ...process.env, RED: red },
  });
  return { ...r, ran: readFileSync(log, 'utf8').trim().split('\n') };
}

test('just check exits 0 and runs the fast, dots and sync suites when all three are green', (t) => {
  const r = check(t, '');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.ran, ['test', 'test-dots', 'test-sync']);
});

test('just check exits 1 naming the sync suite when only it is red', (t) => {
  const r = check(t, 'test-sync');
  assert.equal(r.status, 1);
  assert.match(r.stderr, /red: test-sync$/m);
});

test('just check still runs the dots and sync suites after a red fast suite, and names each red one', (t) => {
  const r = check(t, 'test test-dots');
  assert.equal(r.status, 1);
  assert.deepEqual(r.ran, ['test', 'test-dots', 'test-sync']);
  assert.match(r.stderr, /red: test test-dots$/m);
});
