// dots-notify-phone and its dev fake, run with a scratch HOME and a stub curl that records what it was given.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const bin = new URL('../../bin/dots-notify-phone', import.meta.url).pathname;
const fake = new URL('../../bin/dev-fake-notify-phone', import.meta.url).pathname;
const TOKEN = 'xoxb-test-token-1234';

function scratch(t, { env: localEnv = `SLACK_BOT_TOKEN=${TOKEN}\nSLACK_USER_ID=U0TEST42\nHUB_PEER_TOKEN=other-secret\n`, reply = '{"ok":true}' } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'notify-phone-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const config = join(root, 'config');
  const stubs = join(root, 'stubs');
  const rec = join(root, 'rec');
  for (const d of [join(config, 'hub'), stubs, rec, join(root, 'home')]) mkdirSync(d, { recursive: true });
  if (localEnv !== null) writeFileSync(join(config, 'hub', 'local.env'), localEnv);
  writeFileSync(join(rec, 'reply'), reply);
  // The stub keeps its argv and stdin, and copies the body file the config on stdin points at, since the script removes it on exit.
  writeFileSync(
    join(stubs, 'curl'),
    `#!/bin/bash
echo "$*" >"$STUB_REC/argv"
cat >"$STUB_REC/stdin"
f=$(sed -n 's/^data-binary = "@\\(.*\\)"$/\\1/p' "$STUB_REC/stdin")
[ -z "$f" ] || cp "$f" "$STUB_REC/body"
cat "$STUB_REC/reply"
`,
  );
  chmodSync(join(stubs, 'curl'), 0o755);
  const env = { ...process.env, HOME: join(root, 'home'), XDG_CONFIG_HOME: config, PATH: stubs + delimiter + process.env.PATH, STUB_REC: rec };
  const read = (n) => (existsSync(join(rec, n)) ? readFileSync(join(rec, n), 'utf8') : null);
  return { root, env, read };
}

const run = (ctx, ...args) => spawnSync(bin, args, { env: ctx.env, encoding: 'utf8' });

test('sends one DM naming the title and body, with the token on stdin only', (t) => {
  const ctx = scratch(t);
  const r = run(ctx, 'Lock', 'Saiful is away');
  assert.equal(r.status, 0, r.stderr);
  assert.ok(ctx.read('stdin').includes(TOKEN));
  assert.ok(!ctx.read('argv').includes(TOKEN));
  assert.ok(ctx.read('argv').includes('--max-time 10'));
  const body = JSON.parse(ctx.read('body'));
  assert.equal(body.channel, 'U0TEST42');
  assert.equal(body.text, '*Lock*\nSaiful is away');
});

test('a title with a newline, a bidi control and markup arrives one-lined, stripped and escaped', (t) => {
  const ctx = scratch(t);
  const r = run(ctx, 'cl\naude‮ <b>&', 'x "quoted"\nsecond⁧ line');
  assert.equal(r.status, 0, r.stderr);
  const body = JSON.parse(ctx.read('body'));
  assert.equal(body.text, '*cl aude &lt;b&gt;&amp;*\nx "quoted" second line');
});

test('without local.env, or without the token, it exits 0 with one stderr line and never runs curl', (t) => {
  for (const localEnv of [null, 'SLACK_USER_ID=U0TEST42\n']) {
    const ctx = scratch(t, { env: localEnv });
    const r = run(ctx, 'a', 'b');
    assert.equal(r.status, 0);
    assert.equal(r.stderr.trim().split('\n').length, 1);
    assert.match(r.stderr, /dots-notify-phone/);
    assert.equal(ctx.read('argv'), null);
  }
});

test('Slack answering ok:false exits 1 and names the error', (t) => {
  const ctx = scratch(t, { reply: '{"ok":false,"error":"channel_not_found"}' });
  const r = run(ctx, 'a', 'b');
  assert.equal(r.status, 1);
  assert.match(r.stderr, /channel_not_found/);
});

test('the fake appends one JSON line per call to phone.jsonl', (t) => {
  const ctx = scratch(t);
  const env = { ...ctx.env, DOTS_DEV_DIR: ctx.root };
  spawnSync(fake, ['one', 'a "b"\nc'], { env });
  const r = spawnSync(fake, ['two', 'd'], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const lines = readFileSync(join(ctx.root, 'phone.jsonl'), 'utf8').trim().split('\n');
  assert.deepEqual(
    lines.map((l) => JSON.parse(l)),
    [
      { title: 'one', body: 'a "b"\nc' },
      { title: 'two', body: 'd' },
    ],
  );
});

test('the fake refuses without DOTS_DEV_DIR', (t) => {
  const ctx = scratch(t);
  const env = { ...ctx.env };
  delete env.DOTS_DEV_DIR;
  const r = spawnSync(fake, ['a', 'b'], { env, encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /just dev/);
});
