// Thousands of scratch dirs left in /tmp by the node suites once filled its quota (m17), so every suite runs inside tests/scratch.sh.
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

test('scratch.sh removes what the command left in its TMPDIR and keeps its exit code', (t) => {
  const outer = mkdtempSync(join(tmpdir(), 'dots-scratch-'));
  t.after(() => rmSync(outer, { recursive: true, force: true }));
  const env = { ...process.env, TMPDIR: outer };
  const script = 'mkdir "$TMPDIR/dots-left-behind"; echo "$TMPDIR"; exit 3';
  let out = '';
  try {
    execFileSync(scratch, ['bash', '-c', script], { env, encoding: 'utf8' });
    assert.fail('scratch.sh exited 0');
  } catch (e) {
    assert.equal(e.status, 3);
    out = e.stdout.trim();
  }
  assert.ok(out.startsWith(`${outer}/`), out);
  assert.equal(existsSync(out), false);
});
