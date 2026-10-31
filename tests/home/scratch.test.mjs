// Thousands of scratch dirs left in /tmp by the node suites once filled its quota (m17), so every suite runs inside tests/scratch.sh, whose dir is on disk.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const scratch = join(repo, 'tests/scratch.sh');

test('every node --test in the justfile runs under tests/scratch.sh', () => {
  const lines = readFileSync(join(repo, 'justfile'), 'utf8').split('\n').filter((l) => /\bnode --test\b/.test(l));
  assert.ok(lines.length >= 3, lines.join('\n'));
  assert.deepEqual(lines.filter((l) => !/tests\/scratch\.sh (timeout \d+ )?node --test\b/.test(l)), []);
});

// /tmp is a tmpfs whose per-user quota other sessions' scratch fills (m66, m67), so the dir lives under the cache.
test('scratch.sh runs the command in a TMPDIR under ~/.cache, removes what it left there and keeps its exit code', (t) => {
  const home = mkdtempSync(join(tmpdir(), 'dots-scratch-'));
  t.after(() => rmSync(home, { recursive: true, force: true }));
  const env = { PATH: process.env.PATH, HOME: home };
  const script = 'mkdir "$TMPDIR/dots-left-behind"; echo "$TMPDIR"; exit 3';
  let out = '';
  try {
    execFileSync(scratch, ['bash', '-c', script], { env, encoding: 'utf8' });
    assert.fail('scratch.sh exited 0');
  } catch (e) {
    assert.equal(e.status, 3);
    out = e.stdout.trim();
  }
  assert.ok(out.startsWith(`${home}/.cache/`), out);
  assert.equal(existsSync(out), false);
});

test('XDG_CACHE_HOME names the cache scratch.sh uses', (t) => {
  const home = mkdtempSync(join(tmpdir(), 'dots-scratch-'));
  t.after(() => rmSync(home, { recursive: true, force: true }));
  const out = execFileSync(scratch, ['bash', '-c', 'echo "$TMPDIR"'], { env: { PATH: process.env.PATH, HOME: home, XDG_CACHE_HOME: `${home}/c` }, encoding: 'utf8' }).trim();
  assert.ok(out.startsWith(`${home}/c/`), out);
});
