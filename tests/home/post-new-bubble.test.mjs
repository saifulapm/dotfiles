// post-new's bubble pass reads bubble.db and writes the undue lines back by rename; a bubble or clear made between the two must not be lost.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig, repo } from './mail-rig.mjs';

const hook = join(repo, 'home/dot_config/notmuch/hooks/executable_post-new');

// A command's exit, stdout and stderr, and whether it has ended yet.
function started(env, cmd, args) {
  const w = { done: false };
  const child = spawn(cmd, args, { env });
  let out = '';
  child.stdout.on('data', (d) => (out += d));
  child.stderr.on('data', (d) => (out += d));
  w.p = new Promise((r) => child.on('close', (code) => { w.done = true; r({ code, out }); }));
  return w;
}

function rig(t) {
  const r = mailRig(t);
  for (const id of ['two', 'due', 'keep']) r.deliver({ From: `Ann <ann@people.test>`, Subject: id, 'Message-ID': `<${id}@x.test>` });
  r.notmuch('tag', '+screened', '-new', '--', '*');
  const tags = (id) => r.notmuch('search', '--output=tags', '--', `id:${id}`).split('\n').filter(Boolean);
  const mail = (...args) => started(r.env, join(repo, 'bin/mail'), args);
  // post-new, paused once it has read bubble.db and before it writes the rest back.
  const paused = async () => {
    const pause = join(r.M, 'pause');
    const pass = started({ ...r.env, POST_NEW_BUBBLE_PAUSE: pause }, 'bash', [hook]);
    while (!existsSync(pause)) {
      if (pass.done) throw new Error(`post-new ended without pausing: ${(await pass.p).out}`);
      await new Promise((res) => setTimeout(res, 50));
    }
    return { pass, release: () => unlinkSync(pause) };
  };
  return { ...r, tags, mail, paused };
}

const later = () => Math.floor(Date.now() / 1000) + 30 * 86400;

test('a bubble set while post-new rewrites bubble.db is there afterwards, and a due line in that pass still fires', async (t) => {
  const r = rig(t);
  const keep = `id:keep@x.test ${later()}`;
  r.setDb('bubble.db', `${keep}\nid:due@x.test ${Math.floor(Date.now() / 1000) - 60}\n`);
  r.notmuch('tag', '+bubble', '-inbox', '-unread', '--', 'id:due@x.test');
  const { pass, release } = await r.paused();
  const bubble = r.mail('hey', 'bubble', 'two@x.test', '--at', 'tomorrow 9am');
  await new Promise((res) => setTimeout(res, 1500));
  const early = bubble.done;
  release();
  assert.equal((await pass.p).code, 0);
  const b = await bubble.p;
  assert.equal(b.code, 0, b.out);
  const due = spawnSync('date', ['-d', 'tomorrow 9am', '+%s'], { encoding: 'utf8' }).stdout.trim();
  const lines = r.db('bubble.db').split('\n').filter(Boolean).sort();
  assert.deepEqual(lines, [keep, `id:two@x.test ${due}`].sort());
  for (const tag of ['inbox', 'unread', 'bubbled']) assert.ok(r.tags('due@x.test').includes(tag), `the due thread has ${tag}: ${r.tags('due@x.test')}`);
  assert.equal(early, false, 'the bubble returned while the pass held bubble.db');
});

test('a bubble cleared while post-new rewrites bubble.db stays cleared', async (t) => {
  const r = rig(t);
  const set = await r.mail('hey', 'bubble', 'two@x.test', '--at', 'next month').p;
  assert.equal(set.code, 0, set.out);
  assert.match(r.db('bubble.db'), /^id:two@x\.test \d+$/m);
  const { pass, release } = await r.paused();
  const clear = r.mail('hey', 'clear', 'two@x.test');
  await new Promise((res) => setTimeout(res, 1500));
  const early = clear.done;
  release();
  assert.equal((await pass.p).code, 0);
  const c = await clear.p;
  assert.equal(c.code, 0, c.out);
  assert.doesNotMatch(r.db('bubble.db'), /two@x\.test/);
  assert.equal(early, false, 'the clear returned while the pass held bubble.db');
});

// After the pass post-new still sends away replies (up to 30 s each) and writes the count; a key must not wait for those.
test('a bubble set while post-new runs past its bubble pass returns at once', async (t) => {
  const r = rig(t);
  r.setDb('bubble.db', `id:keep@x.test ${later()}\n`);
  const stubs = join(r.M, 'stubs');
  mkdirSync(stubs);
  const [counting, hold] = [join(r.M, 'counting'), join(r.M, 'hold')];
  writeFileSync(join(stubs, 'kak-mail'), `#!/bin/sh\ntouch ${counting}\nwhile [ -e ${hold} ]; do sleep 0.05; done\n`);
  chmodSync(join(stubs, 'kak-mail'), 0o755);
  writeFileSync(hold, '');
  const pass = started({ ...r.env, PATH: `${stubs}:${r.env.PATH}` }, 'bash', [hook]);
  while (!existsSync(counting)) {
    if (pass.done) throw new Error(`post-new ended before its count: ${(await pass.p).out}`);
    await new Promise((res) => setTimeout(res, 50));
  }
  const bubble = r.mail('hey', 'bubble', 'two@x.test', '--at', 'tomorrow 9am');
  const late = new Promise((res) => setTimeout(() => res({ code: null, out: 'the bubble was still waiting after 10 s' }), 10000));
  let b;
  try {
    b = await Promise.race([bubble.p, late]);
  } finally {
    unlinkSync(hold);
  }
  assert.equal((await pass.p).code, 0);
  assert.equal(b.code, 0, b.out);
  assert.match(r.db('bubble.db'), /^id:two@x\.test \d+$/m);
});

// The pass lets the lock go before the rest of the sync, so a later decision never waits for the fetch.
test('a full mail-sync with no decision in flight ends done with bubble.db\'s undue lines unchanged', (t) => {
  const r = mailRig(t);
  const hooks = join(r.M, 'hooks');
  mkdirSync(hooks);
  copyFileSync(hook, join(hooks, 'post-new'));
  chmodSync(join(hooks, 'post-new'), 0o755);
  const cfg = r.env.NOTMUCH_CONFIG;
  writeFileSync(cfg, readFileSync(cfg, 'utf8').replace('[database]\n', `[database]\nhook_dir=${hooks}\n`));
  const stubs = join(r.M, 'stubs');
  mkdirSync(stubs);
  for (const tool of ['mbsync', 'notify-send']) {
    writeFileSync(join(stubs, tool), '#!/bin/sh\nexit 0\n');
    chmodSync(join(stubs, tool), 0o755);
  }
  r.deliver({ From: 'Ann <ann@people.test>', 'Message-ID': '<two@x.test>' });
  const lines = `id:two@x.test ${later()}\nid:other@x.test ${later() + 1}\n`;
  r.setDb('bubble.db', lines);
  const s = spawnSync(join(repo, 'bin/mail-sync'), ['--quiet'], { env: { ...r.env, PATH: `${stubs}:${r.env.PATH}` }, encoding: 'utf8' });
  assert.equal(s.status, 0, s.stderr);
  assert.match(readFileSync(join(r.env.XDG_STATE_HOME, 'hey-mail/sync.log'), 'utf8'), /mail-sync: done in \d+s$/m);
  assert.equal(r.db('bubble.db'), lines);
});
