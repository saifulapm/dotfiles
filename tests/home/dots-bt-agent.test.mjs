// dots-bt-agent starts with the user manager, so Control's pair has an agent; the old bt-agent is gone from home/.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const units = join(repo, 'home/dot_config/systemd/user');

test('dots-bt-agent runs at login from the repo, and a machine with no adapter skips it', () => {
  const unit = readFileSync(join(units, 'dots-bt-agent.service'), 'utf8');
  assert.match(unit, /^ExecStart=%h\/Codes\/dotfiles\/bin\/dots-bt-agent$/m);
  assert.match(unit, /^ConditionDirectoryNotEmpty=\/sys\/class\/bluetooth$/m);
  assert.match(unit, /^Restart=on-failure$/m);
  assert.match(unit, /^WantedBy=default\.target$/m);
  assert.equal(readFileSync(join(units, 'default.target.wants/symlink_dots-bt-agent.service'), 'utf8').trim(), '../dots-bt-agent.service');
});

test('no bt-agent unit or link is left in home/', () => {
  assert.equal(existsSync(join(units, 'bt-agent.service')), false);
  assert.equal(existsSync(join(units, 'bluetooth.target.wants')), false);
});

test('a machine that ran bt-agent has its unit and link removed', () => {
  const removed = readFileSync(join(repo, 'home/.chezmoiremove'), 'utf8').split('\n');
  for (const f of ['.config/systemd/user/bt-agent.service', '.config/systemd/user/bluetooth.target.wants/bt-agent.service']) assert.ok(removed.includes(f), f);
});
