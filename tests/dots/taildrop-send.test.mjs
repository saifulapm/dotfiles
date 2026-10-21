// dots-taildrop-send with stub tailscale, dots-call, notify-send and picker, each recording what it was given.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const source = new URL('../../bin/dots-taildrop-send', import.meta.url).pathname;

// Like the real CLI, the stub paints progress only when stderr is a terminal: each file reaches 48% and then 100%.
const TAILSCALE = `#!/bin/bash
printf '%s\\n' "$*" >>"$STUB_REC/tailscale"
[ "$1 $2" = "file cp" ] || exit 2
shift 2
files=()
for a in "$@"; do case $a in --*) ;; *:) target=$a ;; *) files+=("$a") ;; esac; done
want=(24 74)
i=0
for f in "\${files[@]}"; do
  [ "$STUB_FAIL" = 1 ] && { echo "can't send to nuc: peer is offline" >&2; exit 1; }
  if [ -t 2 ]; then
    printf '\\r\\033[K%-36s    1.00KiB    2.00KiB/s     48.00%%    ETA 00:00:01' "$(basename "$f")" >&2
    sleep 0.5
    # Whether the island heard 48% while that paint was still the last one, before the next began.
    grep -q "sending progress \${want[i]}\$" "$STUB_REC/dots-call" 2>/dev/null && echo "\${want[i]}" >>"$STUB_REC/timely"
    i=$((i + 1))
    printf '\\r\\033[K%-36s    2.00KiB    2.00KiB/s    100.00%%    ETA 00:00:00\\n' "$(basename "$f")" >&2
  fi
done
`;

function scratch(t, { pick = true, fail = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'taildrop-send-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const stubs = join(root, 'stubs');
  const rec = join(root, 'rec');
  const home = join(root, 'home');
  for (const d of [stubs, rec, home]) mkdirSync(d, { recursive: true });
  const files = ['a.txt', 'b.txt'].map((n) => join(root, n));
  for (const f of files) writeFileSync(f, 'x'.repeat(2048));
  const stub = (name, body) => {
    writeFileSync(join(stubs, name), body);
    chmodSync(join(stubs, name), 0o755);
  };
  stub('tailscale', TAILSCALE);
  // The script calls the dots-call beside it, so a copy runs from the stubs with a recording dots-call next to it.
  copyFileSync(source, join(stubs, 'dots-taildrop-send'));
  chmodSync(join(stubs, 'dots-taildrop-send'), 0o755);
  stub('dots-call', '#!/bin/bash\nprintf \'%s\\n\' "$*" >>"$STUB_REC/dots-call"\n');
  stub('notify-send', '#!/bin/bash\nfor a in "$@"; do printf \'%s\\0\' "$a"; done >"$STUB_REC/notify"\n');
  stub('picker', pick ? `#!/bin/bash\nprintf '%s\\n' '${files[0]}' '${files[1]}'\n` : '#!/bin/bash\nexit 1\n');
  const env = {
    ...process.env,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_STATE_HOME: join(home, '.local/state'),
    XDG_RUNTIME_DIR: join(root, 'run'),
    PATH: stubs + delimiter + process.env.PATH,
    STUB_REC: rec,
    STUB_FAIL: fail ? '1' : '0',
    DOTS_PICK_FILES: join(stubs, 'picker'),
  };
  const read = (n) => (existsSync(join(rec, n)) ? readFileSync(join(rec, n), 'utf8') : null);
  return { files, env, read, bin: join(stubs, 'dots-taildrop-send') };
}

const run = (ctx, ...args) => spawnSync(ctx.bin, args, { env: ctx.env, encoding: 'utf8', timeout: 10000 });

test('sends the picked files, reports start, progress and done to the island, and notifies', (t) => {
  const picked = scratch(t);
  const r = run(picked, 'nuc', '100.88.14.3');
  assert.equal(r.status, 0, r.stderr);
  const cp = picked.read('tailscale').trim();
  assert.match(cp, /^file cp /);
  assert.ok(cp.endsWith(`-- ${picked.files.join(' ')} 100.88.14.3:`), cp);
  const calls = picked.read('dots-call').trim().split('\n');
  assert.equal(calls[0], 'sending start 2 nuc');
  assert.equal(calls.at(-1), 'sending done');
  const pcts = calls.filter((l) => l.startsWith('sending progress ')).map((l) => Number(l.split(' ')[2]));
  // 48% of the first of two equal files is 24% of the whole, then half, then 74%, then all.
  assert.deepEqual(pcts, [24, 50, 74, 100]);
  assert.equal(picked.read('timely'), '24\n74\n', 'each paint reaches the island before the next one starts');
  assert.deepEqual(picked.read('notify').split('\0').slice(0, -1), ['-a', 'Tailscale', '--', 'Sent 2 files to nuc', 'a.txt\nb.txt']);
});

test('files given on the command line skip the picker, and one file is named in the notification', (t) => {
  const ctx = scratch(t);
  const r = run(ctx, 'nuc', '100.88.14.3', ctx.files[0]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(ctx.read('dots-call').split('\n')[0], 'sending start 1 nuc');
  assert.deepEqual(ctx.read('notify').split('\0').slice(0, -1), ['-a', 'Tailscale', '--', 'Sent a.txt to nuc', '']);
});

test('nothing picked sends nothing and tells the island nothing', (t) => {
  const ctx = scratch(t, { pick: false });
  const r = run(ctx, 'nuc', '100.88.14.3');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(ctx.read('tailscale'), null);
  assert.equal(ctx.read('dots-call'), null);
  assert.equal(ctx.read('notify'), null);
});

test('a failed send ends the slot and raises a critical notification with the reason on one line', (t) => {
  const ctx = scratch(t, { fail: true });
  const r = run(ctx, 'nuc', '100.88.14.3', ctx.files[0]);
  assert.equal(r.status, 1);
  assert.equal(ctx.read('dots-call').trim().split('\n').at(-1), 'sending done');
  assert.deepEqual(ctx.read('notify').split('\0').slice(0, -1), ['-u', 'critical', '-a', 'Tailscale', '--', 'Could not send to nuc', "can't send to nuc: peer is offline"]);
});

test('a machine name with a newline, ESC or U+202E reaches the island and the notification as one clean line', (t) => {
  const ctx = scratch(t);
  const r = run(ctx, 'nu\nc\x1b‮', '100.88.14.3', ctx.files[0]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(ctx.read('dots-call').split('\n')[0], 'sending start 1 nu c');
  assert.equal(ctx.read('notify').split('\0')[3], 'Sent a.txt to nu c');
});
