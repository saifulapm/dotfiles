// dots-clip-store as wl-paste --watch runs it, with cliphist replaced by a stub that logs its calls.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawn } from 'node:child_process';

const bin = new URL('../../bin/', import.meta.url).pathname;

function scratch() {
  const root = mkdtempSync(join(tmpdir(), 'dots-clip-'));
  const stubs = join(root, 'stubs');
  mkdirSync(stubs);
  const log = join(root, 'cliphist.log');
  writeFileSync(join(stubs, 'cliphist'), `#!/bin/sh\necho "$*" >>'${log}'\ncat >/dev/null\n`);
  chmodSync(join(stubs, 'cliphist'), 0o755);
  const env = { ...process.env, XDG_STATE_HOME: join(root, 'state'), PATH: stubs + delimiter + process.env.PATH };
  delete env.CLIPBOARD_STATE;
  return { env, log };
}

// Starts the store with text on stdin and the pipe left open, as an owner that stalls mid-copy leaves it.
function stalled(env, text) {
  const p = spawn(join(bin, 'dots-clip-store'), [], { env, stdio: ['pipe', 'ignore', 'ignore'] });
  p.stdin.write(text);
  return { p, done: new Promise((resolve) => p.on('close', (code) => resolve(code))) };
}

// A stalled owner kept the wl-paste watcher's run alive, so no later copy reached the history.
test('a copy whose owner never closes the pipe ends the run within 5 s and stores nothing', async () => {
  const { env, log } = scratch();
  const t0 = Date.now();
  const { p, done } = stalled(env, 'half a clip');
  const code = await Promise.race([done, new Promise((r) => setTimeout(() => r('still running'), 5000))]);
  p.kill('SIGKILL');
  p.stdin.destroy();
  assert.equal(code, 0, `after ${Date.now() - t0} ms the run was ${code}`);
  assert.equal(existsSync(log) && readFileSync(log, 'utf8').includes('store'), false);
});

test('a copy whose owner closes the pipe is stored', async () => {
  const { env, log } = scratch();
  const p = spawn(join(bin, 'dots-clip-store'), [], { env, stdio: ['pipe', 'ignore', 'ignore'] });
  p.stdin.end('a whole clip');
  assert.equal(await new Promise((resolve) => p.on('close', resolve)), 0);
  assert.match(readFileSync(log, 'utf8'), /-max-items 500 store/);
});
