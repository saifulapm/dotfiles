// dots-agents turns amx statusline's ✽N (working) and ⚠N (waiting) into the tmux bar's words, in the margins' words; tmux runs it with sh, where a word starting # is a comment, so colours come without it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const agents = new URL('../../bin/dots-agents', import.meta.url).pathname;

function say(t, amxSays) {
  const dir = mkdtempSync(join(tmpdir(), 'dots-agents-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, 'amx'), `#!/bin/sh\n[ "$1" = statusline ] && printf '%s' '${amxSays}'\n`);
  chmodSync(join(dir, 'amx'), 0o755);
  const r = spawnSync(agents, ['575653', 'c8381e', '1c1915'], { encoding: 'utf8', env: { PATH: dir + delimiter + process.env.PATH } });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
}

test('working reads quietly and waiting after an accent dot, then the margin gap', (t) => {
  assert.equal(say(t, '⚠3\n'), '#[fg=#c8381e]● #[fg=#1c1915]3 waiting#[fg=#575653]   ');
  assert.equal(say(t, '✽2 ⚠1\n'), '#[fg=#575653]2 working   #[fg=#c8381e]● #[fg=#1c1915]1 waiting#[fg=#575653]   ');
});

test('no agent to mention, or no amx at all, prints nothing', (t) => {
  assert.equal(say(t, ''), '');
  const r = spawnSync(agents, ['575653', 'c8381e', '1c1915'], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' } });
  assert.deepEqual([r.status, r.stdout], [0, '']);
});
