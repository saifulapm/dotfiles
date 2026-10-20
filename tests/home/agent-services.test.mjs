// The apply's agent-services step against stub systemctl and workflow, on a scratch home whose PATH holds neither for real.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_30-agents.sh.tmpl'), 'utf8');

const render = (home) => {
  const r = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: script, encoding: 'utf8', env: { PATH: process.env.PATH, HOME: home } });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
};

// run_onchange runs the script again only when its text changes, so the text must change when local.env appears and when the store token lands, and at no other apply.
test('the script re-renders when local.env appears and when the machine joins the store, and only then', () => {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-agents-')));
  const none = render(home);
  assert.equal(render(home), none);
  mkdirSync(join(home, '.config/hub'), { recursive: true });
  writeFileSync(join(home, '.config/hub/local.env'), 'HUB_PEER_TOKEN=x\n');
  const written = render(home);
  writeFileSync(join(home, '.config/hub/local.env'), 'HUB_PEER_TOKEN=y\n');
  assert.equal(render(home), written, 'a rotated token is not a new state');
  writeFileSync(join(home, '.config/hub/local.env'), 'HUB_PEER_TOKEN=y\nHUB_STORE_TOKEN=z\n');
  const joined = render(home);
  assert.equal(new Set([none, written, joined]).size, 3);
  assert.doesNotMatch(joined, /=y|=z/, 'no token reaches the script text');
});

// manager: what systemctl --user is-system-running prints; env: local.env's text, or none.
function apply({ manager = 'running', env, switchFails = false } = {}) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-agents-')));
  mkdirSync(join(home, 'stubs'));
  writeFileSync(join(home, 'stubs/systemctl'), `#!/bin/sh\necho "systemctl $*" >> "$HOME/calls"\n[ "$2" = is-system-running ] && echo ${manager}\nexit 0\n`, { mode: 0o755 });
  writeFileSync(join(home, 'stubs/workflow'), `#!/bin/sh\necho "workflow $*" >> "$HOME/calls"\nexit ${switchFails ? 2 : 0}\n`, { mode: 0o755 });
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

// The dotfiles ship one Remote Control template; a device enables its own projects, so no per-project file is linked here.
test('claude-rc@ runs in ~/Codes/<project>, skips a missing folder, and no instance is enabled from the dotfiles', () => {
  const units = join(repo, 'home/dot_config/systemd/user');
  const unit = readFileSync(join(units, 'claude-rc@.service'), 'utf8');
  assert.match(unit, /^ConditionPathIsDirectory=%h\/Codes\/%i$/m);
  assert.match(unit, /^WorkingDirectory=%h\/Codes\/%i$/m);
  assert.match(unit, /^ExecStart=%h\/\.local\/bin\/claude remote-control --spawn worktree --permission-mode bypassPermissions --no-create-session-in-dir$/m);
  assert.match(unit, /^WantedBy=default\.target$/m);
  const linked = readdirSync(units, { recursive: true }).filter((f) => /claude-rc@/.test(f) && f !== 'claude-rc@.service');
  assert.deepEqual(linked, []);
});

// run_onchange records a script that exits 0, so a join that failed has to fail the script to be tried on the next apply.
test('a refused store join fails the step, naming it', () => {
  const { r } = apply({ env: 'HUB_PEER_TOKEN=x\n', switchFails: true });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /dots: workflow switch did not join the mem store/);
});
