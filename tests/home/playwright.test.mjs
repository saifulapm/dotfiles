// The playwright-cli wrapper and the mise step that installs it, against stub mise and playwright-cli binaries on a scratch home.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const wrapper = join(repo, 'bin/playwright-cli');
const miseScript = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_19-mise.sh.tmpl'), 'utf8');

function exe(path, body) {
  writeFileSync(path, body, { mode: 0o755 });
  chmodSync(path, 0o755);
}

// The stub real binary logs its argv; the stub mise prints it for `which playwright-cli` and logs every call.
function scratch() {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-playwright-')));
  mkdirSync(join(home, 'stubs'));
  mkdirSync(join(home, 'real'));
  mkdirSync(join(home, 'node'));
  exe(join(home, 'real/playwright-cli'), '#!/bin/sh\necho "$*" >> "$HOME/real.log"\n');
  exe(
    join(home, 'stubs/mise'),
    `#!/bin/sh
echo "$*" >> "$HOME/mise.log"
case "$*" in
  "which playwright-cli") echo "$HOME/real/playwright-cli" ;;
  "where node") echo "$HOME/node" ;;
esac
`,
  );
  const env = { PATH: `${home}/stubs:/usr/bin:/bin`, HOME: home, XDG_CONFIG_HOME: join(home, '.config') };
  return { home, env };
}

function calls(home, name = 'real.log') {
  const log = join(home, name);
  return existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n') : [];
}

function withConfig(home) {
  mkdirSync(join(home, '.config/playwright'), { recursive: true });
  writeFileSync(join(home, '.config/playwright/cli.config.json'), '{}');
  return join(home, '.config/playwright/cli.config.json');
}

test('--version reaches the real binary unchanged', () => {
  const { home, env } = scratch();
  const r = spawnSync('bash', [wrapper, '--version'], { encoding: 'utf8', env, cwd: home });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(home), ['--version']);
});

test('open gets the machine config unless the project or the caller supplies one', () => {
  const { home, env } = scratch();
  const config = withConfig(home);
  const run = (...args) => spawnSync('bash', [wrapper, ...args], { encoding: 'utf8', env, cwd: home });

  assert.equal(run('open', 'https://example.com').status, 0);
  assert.equal(run('open', 'https://example.com', '--config', 'x').status, 0);
  assert.equal(run('snapshot').status, 0);
  assert.deepEqual(calls(home), [`open https://example.com --config ${config}`, 'open https://example.com --config x', 'snapshot']);

  mkdirSync(join(home, '.playwright'));
  writeFileSync(join(home, '.playwright/cli.config.json'), '{}');
  assert.equal(run('open', 'https://example.org').status, 0);
  assert.equal(calls(home).at(-1), 'open https://example.org');
});

// The wrapper is first on PATH, so a PATH lookup for playwright-cli would find itself.
test('the wrapper finds the real binary through mise, not PATH', () => {
  const { home, env } = scratch();
  mkdirSync(join(home, 'self'));
  exe(join(home, 'self/playwright-cli'), readFileSync(wrapper, 'utf8'));
  const r = spawnSync(join(home, 'self/playwright-cli'), ['--version'], { encoding: 'utf8', env: { ...env, PATH: `${home}/self:${env.PATH}` }, cwd: home, timeout: 5000 });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(home), ['--version']);
  assert.deepEqual(calls(home, 'mise.log'), ['which playwright-cli']);
});

test('the mise step runs the real playwright-cli install --skills --global once', () => {
  const { home, env } = scratch();
  const rendered = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: miseScript, encoding: 'utf8', env });
  assert.equal(rendered.status, 0, rendered.stderr);
  const r = spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env, cwd: home });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(home), ['install --skills --global']);
  assert.equal(calls(home, 'mise.log')[0], 'install');
});

test('mise puts the dotfiles bin dir ahead of every tool bin dir', () => {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-playwright-env-')));
  const env = {
    PATH: process.env.PATH,
    HOME: home,
    MISE_GLOBAL_CONFIG_FILE: join(repo, 'home/dot_config/mise/config.toml'),
    MISE_DATA_DIR: join(home, 'data'),
    MISE_CACHE_DIR: join(home, 'cache'),
    MISE_STATE_DIR: join(home, 'state'),
    MISE_CONFIG_DIR: join(home, 'config'),
    XDG_CONFIG_HOME: join(home, 'xdg/config'),
    XDG_DATA_HOME: join(home, 'xdg/data'),
    XDG_CACHE_HOME: join(home, 'xdg/cache'),
    XDG_STATE_HOME: join(home, 'xdg/state'),
  };
  const r = spawnSync('mise', ['env', '--paths'], { encoding: 'utf8', env, cwd: home });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.split('\n')[0], join(home, 'Sites/github/dotfiles/bin'));
});
