// A throwaway tmux server on the repo's tmux.conf, started from bash as an agent's or a script's would be.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const conf = new URL('../../home/dot_config/tmux/tmux.conf', import.meta.url).pathname;

test('a new tmux pane runs fish, whatever shell started the server', (t) => {
  const sock = `dots-tmux-${process.pid}`;
  const env = { ...process.env, SHELL: '/bin/bash' };
  delete env.TMUX;
  const tmux = (...a) => execFileSync('tmux', ['-L', sock, ...a], { env, encoding: 'utf8' }).trim();
  t.after(() => { try { tmux('kill-server'); } catch {} });
  tmux('-f', conf, 'new-session', '-d', '-x', '80', '-y', '24');
  tmux('split-window', '-d');
  let commands = '';
  for (let i = 0; i < 50 && commands !== 'fish\nfish'; i++) {
    execFileSync('sleep', ['0.1']);
    commands = tmux('list-panes', '-F', '#{pane_current_command}');
  }
  assert.equal(commands, 'fish\nfish');
});
