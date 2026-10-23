// bt-agent confirms every pairing request, so Control's pair completes on a device that shows a passkey.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');
const unit = read('home/dot_config/systemd/user/bt-agent.service');

test('bt-agent runs at login with NoInputNoOutput, and a machine with no adapter skips it', () => {
  assert.match(unit, /^ConditionDirectoryNotEmpty=\/sys\/class\/bluetooth$/m);
  assert.match(unit, /^ExecStart=\/usr\/bin\/bt-agent -c NoInputNoOutput$/m);
  assert.match(unit, /^Restart=on-failure$/m);
  assert.match(unit, /^WantedBy=default\.target$/m);
  assert.equal(read('home/dot_config/systemd/user/default.target.wants/symlink_bt-agent.service').trim(), '../bt-agent.service');
});

test('bt-agent waits for bluetoothd on the system bus instead of failing', () => {
  const pre = unit.match(/^ExecStartPre=\/bin\/sh -c '(.*)'$/m);
  assert.ok(pre, 'an ExecStartPre waits');
  assert.match(unit, /^TimeoutStartSec=infinity$/m);
  // A busctl that finds org.bluez on its third ask, as when bluetoothd starts after the user manager.
  const dir = realpathSync(mkdtempSync(join(tmpdir(), 'bt-agent-test-')));
  writeFileSync(join(dir, 'busctl'), `#!/bin/sh\necho "$*" >> ${dir}/log\n[ "$(wc -l < ${dir}/log)" -ge 3 ]\n`);
  chmodSync(join(dir, 'busctl'), 0o755);
  const r = spawnSync('/bin/sh', ['-c', pre[1]], { encoding: 'utf8', env: { PATH: `${dir}:/usr/bin:/bin` }, timeout: 10000 });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(readFileSync(join(dir, 'log'), 'utf8').trim().split('\n'), Array(3).fill('--system status org.bluez'));
});
