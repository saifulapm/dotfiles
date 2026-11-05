import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const call = new URL('../../bin/dots-call', import.meta.url).pathname;

// qs ipc prints "Target not found." and exits 0, so a bind or a script calling a surface that is gone would read it as done.
const run = (t, answer, ...args) => {
  const dir = mkdtempSync(join(tmpdir(), 'dots-call-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, 'qs'), `#!/bin/sh\nprintf '%s\\n' '${answer}'\n`);
  chmodSync(join(dir, 'qs'), 0o755);
  return spawnSync(call, args, { env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, XDG_RUNTIME_DIR: dir, WAYLAND_DISPLAY: '' }, encoding: 'utf8' });
};

test('a target or function qs ipc cannot find exits 1 and says so', (t) => {
  for (const answer of ['Target not found.', 'Function not found.']) {
    const r = run(t, answer, 'themes', 'toggle');
    assert.equal(r.status, 1, answer);
    assert.equal(r.stdout, '');
    assert.match(r.stderr, new RegExp(`themes toggle: ${answer}`));
  }
});

test("qs ipc's answer to a call it found is printed and exits 0", (t) => {
  const r = run(t, '{"open":false}', 'launcher', 'state');
  assert.equal(r.status, 0);
  assert.equal(r.stdout, '{"open":false}\n');
});
