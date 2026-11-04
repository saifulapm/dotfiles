import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { words } from './newtab.mjs';

const render = new URL('./theme-render.mjs', import.meta.url).pathname;

// The fragments dots colorscheme writes, read back from a scratch state dir.
function fragments(t, name) {
  const state = mkdtempSync(join(tmpdir(), 'dots-engraved-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const r = spawnSync(process.execPath, [render, name], { env: Object.assign({}, process.env, { XDG_STATE_HOME: state }), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return (f) => readFileSync(join(state, 'dots/theme-out', f), 'utf8');
}

test('the new tab says its keys bare in the engraved voice and in brackets in Blueprint\'s', () => {
  const bare = words('bracket', true);
  assert.equal(bare.go, '↵ GO');
  assert.deepEqual(bare.keys[3], ['↵', 'GO']);
  const marked = words('bracket');
  assert.equal(marked.go, '[↵] GO');
  assert.deepEqual(marked.keys[3], ['[↵]', 'GO']);
});

test('Hi-Fi\'s new tab takes Blueprint\'s look and says it is engraved', (t) => {
  const html = fragments(t, 'hi-fi')('chromium-newtab/newtab.html');
  assert.match(html, /<html lang="en" data-voice="bracket" data-engraved="true" data-theme="hi-fi">/);
  assert.match(fragments(t, 'blueprint')('chromium-newtab/newtab.html'), /<html lang="en" data-voice="bracket" data-theme="blueprint">/);
});

test('Hi-Fi\'s tmux bar numbers its windows bare, in Blueprint\'s colours and separator', (t) => {
  const tmux = fragments(t, 'hi-fi')('tmux.conf');
  const line = (k) => tmux.split('\n').find((l) => l.startsWith(`set -g ${k} `));
  assert.match(line('window-status-current-format'), /^set -g window-status-current-format "#\[fg=#fabd2f\]#\{\?#\{e\|<:#\{window_index\},10\},0,\}#\{window_index\}#\[fg=#ebdbb2\] /);
  assert.match(line('window-status-format'), /^set -g window-status-format "#\[fg=#a89984\]#\{\?#\{e\|<:#\{window_index\},10\},0,\}#\{window_index\} /);
  assert.match(line('window-status-separator'), / · "$/);
  assert.match(tmux, /#\(dots-agents bracket /);
});

test('Hi-Fi\'s kak-mail key strip reads its keys bare', (t) => {
  const kak = fragments(t, 'hi-fi')('dots.kak');
  const keys = kak.match(/set-option global mail_keys '(.*)'/)[1];
  assert.match(keys, /^\{MailKey\}↵\{MailStrip\} OPEN · /);
  assert.match(fragments(t, 'blueprint')('dots.kak'), /set-option global mail_keys '\{MailKey\}\[↵\]\{MailStrip\} OPEN · /);
});
