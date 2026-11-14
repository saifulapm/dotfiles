// The box list lives once, in bin/mail_engine.py; hey-folder-sync and the post-new hook keep their own tag queries, and these tests pin that the three agree.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { repo } from './mail-rig.mjs';

function engineBoxes() {
  const r = spawnSync('python3', ['-B', '-c', 'import json, mail_engine; print(json.dumps({b[1]: b[2] for b in mail_engine.BOXES}))'], {
    env: { PATH: '/usr/bin:/bin', PYTHONPATH: join(repo, 'bin') },
    encoding: 'utf8',
  });
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}

test("the engine's boxes select what hey-folder-sync files into each HEY folder", () => {
  const rules = Object.fromEntries([...readFileSync(join(repo, 'bin/hey-folder-sync'), 'utf8').matchAll(/^rule "[^"]+"\s+"([^"]+)"\s+'([^']+)'$/gm)].map((m) => [m[1], m[2]]));
  const boxes = engineBoxes();
  for (const name of ['Screener', 'Paper Trail', 'Reply Later', 'Set Aside', 'Read']) assert.equal(boxes[name], rules[name], name);
  // HEY/Feed holds all of the Feed, and the box shows what is new in it.
  assert.equal(boxes['The Feed'], `${rules['The Feed']} and tag:unread`);
});

test("the post-new hook counts the engine's Imbox and Screener", () => {
  const hook = readFileSync(join(repo, 'home/dot_config/notmuch/hooks/executable_post-new'), 'utf8');
  const boxes = engineBoxes();
  assert.equal(hook.match(/^\s*imbox=\$\(count (.+)\)$/m)?.[1], boxes.Imbox);
  assert.equal(hook.match(/^\s*screener=\$\(count (.+)\)$/m)?.[1], boxes.Screener);
});

test('kak-mail holds no box query of its own', () => {
  assert.doesNotMatch(readFileSync(join(repo, 'bin/kak-mail'), 'utf8'), /tag:screened/);
});
