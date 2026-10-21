// dots-hub-serve with a tailscale stub first on PATH: the stub answers status --json from a list of backend states, one per call, and records every other call.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const bin = new URL('../../bin/dots-hub-serve', import.meta.url).pathname;
const units = new URL('../../home/dot_config/systemd/user/', import.meta.url).pathname;

// states: the BackendState of each status call in turn, the last one repeating; "down" stands for a tailscaled that is not running.
function run(states, { serveFails = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'hub-serve-'));
  writeFileSync(join(root, 'states'), states.join('\n') + '\n');
  writeFileSync(
    join(root, 'tailscale'),
    `#!/bin/sh
if [ "$1 $2" = "status --json" ]; then
  s=$(head -n1 ${root}/states)
  [ "$(wc -l < ${root}/states)" -gt 1 ] && sed -i 1d ${root}/states
  echo status >> ${root}/calls
  [ "$s" = down ] && { echo "failed to connect to local tailscaled" >&2; exit 1; }
  printf '{"BackendState":"%s"}\\n' "$s"
  exit 0
fi
echo "$*" >> ${root}/calls
${serveFails ? 'echo "serve config denied" >&2; exit 1' : 'exit 0'}
`,
  );
  chmodSync(join(root, 'tailscale'), 0o755);
  const r = spawnSync(bin, { encoding: 'utf8', env: { PATH: root + delimiter + process.env.PATH, DOTS_HUB_SERVE_INTERVAL: '0.01' } });
  const calls = existsSync(join(root, 'calls')) ? readFileSync(join(root, 'calls'), 'utf8').trim().split('\n') : [];
  return { ...r, calls };
}

const serve = 'serve --bg --tcp 8789 tcp://localhost:8789';

test('a running tailscale serves the hub on tcp 8789 of the tailnet address', () => {
  const r = run(['Running']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.calls, ['status', serve]);
});

test('a tailscale that comes up within the wait is served once it runs', () => {
  const r = run(['down', 'NeedsLogin', 'Starting', 'Running']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.calls, ['status', 'status', 'status', 'status', serve]);
});

test('a tailscale that never runs is not served, and the wait gives up quietly after 30 tries', () => {
  for (const state of ['NeedsLogin', 'down']) {
    const r = run([state]);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(r.calls, Array(30).fill('status'), state);
    assert.match(r.stderr, /tailscale is not running/, state);
  }
});

test('a refused serve says so and still exits 0, so the hub keeps running', () => {
  const r = run(['Running'], { serveFails: true });
  assert.equal(r.status, 0);
  assert.deepEqual(r.calls, ['status', serve]);
  assert.match(r.stderr, /other machines cannot reach this hub/);
});

// The hub reads its tailnet name once, as it starts; started at boot before tailscale runs, it named itself by its bare machine name, which no peer lists.
test('hub-local waits on dots-hub-serve before the hub starts, and ignores how it ends', () => {
  const unit = readFileSync(join(units, 'hub-local.service'), 'utf8');
  assert.match(unit, /^ExecStartPre=-%h\/Codes\/dotfiles\/bin\/dots-hub-serve$/m);
  assert.doesNotMatch(unit, /^ExecStartPost=/m);
  assert.ok(readdirSync(new URL('../../bin/', import.meta.url).pathname).includes('dots-hub-serve'));
});
