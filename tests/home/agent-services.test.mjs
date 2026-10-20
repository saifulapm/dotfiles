// The apply's agent-services step against stub systemctl and workflow, on a scratch home whose PATH holds neither for real.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_after_30-agents.sh.tmpl'), 'utf8');

// manager: what systemctl --user is-system-running prints; env: local.env's text, or none.
function apply({ manager = 'running', env } = {}) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-agents-')));
  mkdirSync(join(home, 'stubs'));
  writeFileSync(join(home, 'stubs/systemctl'), `#!/bin/sh\necho "systemctl $*" >> "$HOME/calls"\n[ "$2" = is-system-running ] && echo ${manager}\nexit 0\n`, { mode: 0o755 });
  writeFileSync(join(home, 'stubs/workflow'), '#!/bin/sh\necho "workflow $*" >> "$HOME/calls"\n', { mode: 0o755 });
  if (env !== undefined) {
    mkdirSync(join(home, '.config/hub'), { recursive: true });
    writeFileSync(join(home, '.config/hub/local.env'), env);
  }
  const vars = { PATH: `${home}/stubs:/usr/bin:/bin`, HOME: home };
  const rendered = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: script, encoding: 'utf8', env: vars });
  assert.equal(rendered.status, 0, rendered.stderr);
  const r = spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env: vars });
  const calls = existsSync(join(home, 'calls')) ? readFileSync(join(home, 'calls'), 'utf8').trim().split('\n') : [];
  return { r, calls };
}

test('with a user manager, the apply starts pxy and the local hub', () => {
  const { r, calls } = apply();
  assert.equal(r.status, 0, r.stderr);
  assert.ok(calls.includes('systemctl --user daemon-reload'), calls.join('\n'));
  assert.ok(calls.some((c) => /^systemctl --user start .*\bpxy\.service\b/.test(c) && /\bhub-local\.service\b/.test(c)), calls.join('\n'));
});

// An install's container and a first boot's tty have no user manager to start anything in.
test('without a user manager, the apply starts nothing and still succeeds', () => {
  const { r, calls } = apply({ manager: 'offline' });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls.filter((c) => !c.endsWith('is-system-running')), []);
});

test('the first apply after dots secrets joins the mem store once', () => {
  const { r, calls } = apply({ env: 'HUB_PEER_TOKEN=x\n' });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls.filter((c) => c.startsWith('workflow')), ['workflow switch --store wss://mem.on-rexa.com/store/share']);
});

test('a machine already in the store, or without local.env, runs no workflow switch', () => {
  for (const env of ['HUB_PEER_TOKEN=x\nHUB_STORE_TOKEN=y\n', undefined]) {
    const { r, calls } = apply({ env });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(calls.filter((c) => c.startsWith('workflow')), [], String(env));
  }
});
