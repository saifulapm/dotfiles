// dots-agents turns amx statusline's ✽N (working) and ⚠N (waiting) into the tmux bar's words, in each theme's margin voice; tmux runs it with sh, where a word starting # is a comment, so colours come without it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const agents = new URL('../../bin/dots-agents', import.meta.url).pathname;

function say(t, amxSays, voice) {
  const dir = mkdtempSync(join(tmpdir(), 'dots-agents-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, 'amx'), `#!/bin/sh\n[ "$1" = statusline ] && printf '%s' '${amxSays}'\n`);
  chmodSync(join(dir, 'amx'), 0o755);
  const r = spawnSync(agents, [voice, '575653', 'c8381e', '1c1915'], { encoding: 'utf8', env: { PATH: dir + delimiter + process.env.PATH } });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
}

test('Paper says working quietly and WAITING in its accent, then the margin dash', (t) => {
  assert.equal(say(t, '✽2 ⚠1\n', 'caps'), '#[fg=#575653]2 WORKING · #[fg=#c8381e,bold]1 WAITING#[nobold]#[fg=#575653] — ');
});

test('Artboard puts its accent dot before waiting, in plain words', (t) => {
  assert.equal(say(t, '⚠3\n', 'plain'), '#[fg=#c8381e]● #[fg=#1c1915]3 waiting#[fg=#575653]   ');
});

test('Blueprint says RUN and WAIT, the wait in its alert colour', (t) => {
  assert.equal(say(t, '✽1\n', 'bracket'), '#[fg=#575653]1 RUN#[fg=#575653] · ');
  assert.equal(say(t, '✽1 ⚠2\n', 'bracket'), '#[fg=#575653]1 RUN · #[fg=#c8381e]2 WAIT#[fg=#575653] · ');
});

test('no agent to mention, or no amx at all, prints nothing', (t) => {
  assert.equal(say(t, '', 'caps'), '');
  const r = spawnSync(agents, ['caps', '575653', 'c8381e', '1c1915'], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' } });
  assert.deepEqual([r.status, r.stdout], [0, '']);
});
