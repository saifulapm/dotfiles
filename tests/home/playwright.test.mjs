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

// The stub real binary logs its argv; the stub mise prints it for `which playwright-cli` and logs every call, and like mise refuses to run where an untrusted mise.toml is.
function scratch() {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-playwright-')));
  mkdirSync(join(home, 'stubs'));
  mkdirSync(join(home, 'real'));
  mkdirSync(join(home, 'node'));
  exe(join(home, 'real/playwright-cli'), '#!/bin/sh\necho "$*" >> "$HOME/real.log"\n');
  exe(
    join(home, 'stubs/mise'),
    `#!/bin/sh
dir=$PWD
if [ "$1" = -C ]; then dir=$2; shift 2; fi
if [ -f "$dir/mise.toml" ]; then echo "mise ERROR Config files in $dir/mise.toml are not trusted." >&2; exit 1; fi
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

// A clone under ~/Tries keeps an untrusted mise.toml, and mise refuses every command run from inside it.
test('the wrapper reaches the real binary from a folder with an untrusted mise.toml', () => {
  const { home, env } = scratch();
  mkdirSync(join(home, 'tries/x'), { recursive: true });
  writeFileSync(join(home, 'tries/x/mise.toml'), '[tools]\njq = "latest"\n');
  const r = spawnSync('bash', [wrapper, '--version'], { encoding: 'utf8', env, cwd: join(home, 'tries/x') });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(home), ['--version']);
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
  assert.equal(r.stdout.split('\n')[0], join(home, 'Codes/dotfiles/bin'));
});

// Playwright's own Chromium is a download pinned to its revision, which a playwright-cli bump leaves missing, so open uses Fedora's.
test('the config open gets launches Fedora\'s chromium with the desktop scaling features', () => {
  const config = JSON.parse(readFileSync(join(repo, 'home/dot_config/playwright/cli.config.json'), 'utf8'));
  assert.equal(config.browser.launchOptions.executablePath, '/usr/bin/chromium-browser');
  assert.deepEqual(config.browser.launchOptions.args, ['--enable-features=CDPScreenshotNewSurface,WaylandPerSurfaceScale,WaylandUiScale']);
});

// Playwright launches Chromium with --no-sandbox unless asked, and an agent browsing the open web should not run a browser bug as the user.
test('every playwright config launches chromium with its sandbox on', () => {
  for (const file of ['home/dot_config/playwright/cli.config.json', 'home/dot_config/playwright-cli/config.json'])
    assert.equal(JSON.parse(readFileSync(join(repo, file), 'utf8')).browser.launchOptions.chromiumSandbox, true, file);
});

// Stubs for the attach path: a token printer, and a systemd-run that leaves the lock a started chromium would.
function withDesktopChromium(home, token = 'tok-1') {
  exe(join(home, 'stubs/playwright-extension-token'), token === null ? '#!/bin/sh\nexit 1\n' : `#!/bin/sh\necho ${token}\n`);
  exe(join(home, 'stubs/systemd-run'), '#!/bin/sh\necho "$*" >> "$HOME/systemd.log"\nmkdir -p "$HOME/.config/chromium"\nln -sf "host-$PPID" "$HOME/.config/chromium/SingletonLock"\n');
  exe(join(home, 'real/playwright-cli'), '#!/bin/sh\necho "$*" >> "$HOME/real.log"\necho "${PLAYWRIGHT_MCP_EXTENSION_TOKEN-none}" >> "$HOME/token.log"\n');
}

test('a local attach to the desktop chromium starts it as its own unit and passes the extension token', () => {
  const { home, env } = scratch();
  withDesktopChromium(home);
  const run = (extra, ...args) => spawnSync('bash', [wrapper, ...args], { encoding: 'utf8', env: { ...env, XDG_RUNTIME_DIR: home, ...extra }, cwd: home });

  assert.equal(run({}, 'attach', '--extension=chromium').status, 0);
  assert.deepEqual(calls(home), ['attach --extension=chromium --idle-timeout=1800000']);
  assert.deepEqual(calls(home, 'token.log'), ['tok-1']);
  assert.match(calls(home, 'systemd.log')[0], /chromium-browser$/);

  assert.equal(run({ PLAYWRIGHT_MCP_EXTENSION_TOKEN: 'mine' }, 'attach', '--extension=chromium').status, 0);
  assert.equal(calls(home, 'token.log').at(-1), 'mine');
});

test('an attach still runs, with no token, before the extension has made one', () => {
  const { home, env } = scratch();
  withDesktopChromium(home, null);
  const r = spawnSync('bash', [wrapper, 'attach', '--extension=chromium'], { encoding: 'utf8', env: { ...env, XDG_RUNTIME_DIR: home }, cwd: home });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls(home, 'token.log'), ['none']);
});

// chromium-tabs closes an ended session's tabs, so detach is all an agent runs.
test('close on the desktop chromium\'s session is refused until it is detached', () => {
  const { home, env } = scratch();
  withDesktopChromium(home);
  const run = (...args) => spawnSync('bash', [wrapper, ...args], { encoding: 'utf8', env: { ...env, XDG_RUNTIME_DIR: home }, cwd: home });

  run('attach', '--extension=chromium');
  const refused = run('-s=chromium', 'close');
  assert.equal(refused.status, 2);
  assert.match(refused.stderr, /detach/);

  assert.equal(run('-s=chromium', 'detach').status, 0);
  assert.equal(calls(home).at(-1), '-s=chromium detach');

  // The session is gone, so the same name is an isolated browser's again.
  assert.equal(run('-s=chromium', 'close').status, 0);
  assert.equal(calls(home).at(-1), '-s=chromium close');
});

test('detach and close of an isolated session pass through unchanged', () => {
  const { home, env } = scratch();
  const run = (...args) => spawnSync('bash', [wrapper, ...args], { encoding: 'utf8', env: { ...env, XDG_RUNTIME_DIR: home }, cwd: home });
  assert.equal(run('-s=op', 'detach').status, 0);
  assert.equal(run('-s=op', 'close').status, 0);
  assert.deepEqual(calls(home), ['-s=op detach', '-s=op close']);
});

test('an attach keeps the idle timeout its caller names', () => {
  const { home, env } = scratch();
  withDesktopChromium(home);
  spawnSync('bash', [wrapper, 'attach', '--extension=chromium', '--idle-timeout=5'], { encoding: 'utf8', env: { ...env, XDG_RUNTIME_DIR: home }, cwd: home });
  assert.deepEqual(calls(home), ['attach --extension=chromium --idle-timeout=5']);
});

test('chromium-tabs closes only the tabs of a grey Playwright group', async () => {
  const removed = [];
  const listeners = {};
  globalThis.chrome = {
    tabGroups: { onUpdated: { addListener: (f) => (listeners.updated = f) }, query: async () => [] },
    tabs: { query: async ({ groupId }) => [{ id: groupId * 10 }, { id: groupId * 10 + 1 }], remove: async (ids) => removed.push(...ids) },
    runtime: { onStartup: { addListener() {} }, onInstalled: { addListener() {} } },
  };
  await import(join(repo, 'home/dot_local/share/dots/chromium-tabs/bg.js'));
  await listeners.updated({ id: 1, color: 'green', title: 'Playwright · cli' });
  await listeners.updated({ id: 2, color: 'grey', title: 'Work' });
  await listeners.updated({ id: 3, color: 'grey' });
  assert.deepEqual(removed, []);
  await listeners.updated({ id: 4, color: 'grey', title: 'Playwright · cli' });
  assert.deepEqual(removed, [40, 41]);
});
