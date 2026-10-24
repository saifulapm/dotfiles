// The chezmoi source applied to a scratch home gives a quiet fish with its aliases and a per-machine history, and a single-excludes git config with both accounts' url rewrites.
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
const fishDir = join(repo, 'home/dot_config/fish');
const gitDir = join(repo, 'home/dot_config/git');

let root, home, env;

before(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'fishgit-')));
  home = join(root, 'home');
  mkdirSync(home);
  writeFileSync(join(root, 'chezmoi.toml'), `sourceDir = "${repo}"\nmode = "symlink"\n[data]\n    machine = "test"\n`);
  env = {
    PATH: process.env.PATH,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_DATA_HOME: join(home, '.local/share'),
    XDG_STATE_HOME: join(home, '.local/state'),
    GIT_CONFIG_NOSYSTEM: '1',
  };
  const applied = spawnSync(
    'chezmoi',
    ['--config', join(root, 'chezmoi.toml'), '--source', repo, '--destination', home, 'apply', '--exclude', 'scripts'],
    { env, encoding: 'utf8' },
  );
  assert.equal(applied.status, 0, applied.stderr);
});

after(() => rmSync(root, { recursive: true, force: true }));

// From the scratch home, so mise does not walk up into the real home's config.
const run = (cmd, args) => spawnSync(cmd, args, { env, cwd: home, encoding: 'utf8' });
const files = (dir) => { try { return readdirSync(dir); } catch { return []; } };

test('fish starts quietly, plain and interactive', () => {
  for (const flags of [['-c'], ['-i', '-c']]) {
    const r = run('fish', [...flags, 'echo ok']);
    assert.equal(r.stdout, 'ok\n', flags.join(' '));
    assert.equal(r.stderr, '', flags.join(' '));
  }
});

test('every kept alias and function is defined, and none is named for a dropped tool', () => {
  const aliases = files(join(fishDir, 'conf.d'))
    .flatMap((f) => readFileSync(join(fishDir, 'conf.d', f), 'utf8').split('\n'))
    .map((l) => /^alias (\S+)/.exec(l)?.[1])
    .filter(Boolean);
  const fns = files(join(fishDir, 'functions')).map((f) => f.replace(/\.fish$/, ''));
  for (const name of ['gst', 'a', 'ssh', 'la', 'cd', 'zd', 'gwd', 'gwp', 'tdl', 'tdlm', 'tsl', 'rsw', 'lsw', 'dsw']) assert.ok(aliases.concat(fns).includes(name), `${name} is kept`);
  const r = run('fish', ['-i', '-c', 'for n in $argv; functions -q $n; or echo missing $n; end', ...aliases, ...fns]);
  assert.equal(r.stdout, '');
  const dropped = run('fish', ['-i', '-c', 'for n in herdr kitty vicinae h hds hdl; functions -q $n; and echo $n; end']);
  assert.equal(dropped.stdout, '');
});

test('the tool directories that exist join PATH, and SSH asks pinentry for curses', () => {
  for (const d of ['.cargo/bin', '.opencode/bin', '.local/share/pnpm', '.local/share/go/bin', 'Android/Sdk/platform-tools', 'Android/Sdk/cmdline-tools/latest/bin', 'Android/Sdk/emulator', '.local/share/mise/shims']) mkdirSync(join(home, d), { recursive: true });
  const r = run('fish', ['-i', '-c', 'string join \\n -- $PATH; echo "go=$GOBIN pnpm=$PNPM_HOME android=$ANDROID_HOME"']);
  const lines = r.stdout.trim().split('\n');
  for (const d of ['.cargo/bin', '.local/share/pnpm', '.local/share/go/bin', 'Android/Sdk/platform-tools', 'Android/Sdk/cmdline-tools/latest/bin', 'Android/Sdk/emulator', '.local/share/mise/shims']) {
    assert.ok(lines.includes(join(home, d)), `${d} on PATH`);
  }
  assert.ok(!lines.includes(join(home, '.opencode/bin')), 'opencode is not on PATH');
  assert.equal(lines.at(-1), `go=${home}/.local/share/go/bin pnpm=${home}/.local/share/pnpm android=${home}/Android/Sdk`);
  const ssh = spawnSync('fish', ['-i', '-c', 'echo $PINENTRY_USER_DATA'], { env: { ...env, SSH_CONNECTION: '1 2 3 4' }, cwd: home, encoding: 'utf8' });
  assert.equal(ssh.stdout, 'curses\n');
});

test('cd goes to a real directory, and jumps through zoxide for the rest', () => {
  mkdirSync(join(home, 'Codes/deep/projx'), { recursive: true });
  const r = run('fish', ['-i', '-c', 'zoxide add ~/Codes/deep/projx; cd ~/Codes; pwd; cd projx >/dev/null; pwd']);
  assert.equal(r.stdout, `${home}/Codes\n${home}/Codes/deep/projx\n`, r.stderr);
});

test('gwd removes the worktree it stands in and its branch, once asked', () => {
  const repo = join(home, 'gwrepo');
  mkdirSync(repo);
  const git = (...a) => spawnSync('git', ['-C', repo, ...a], { env, encoding: 'utf8' });
  git('init', '-q', '-b', 'main');
  git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '--allow-empty', '-m', 'init');
  git('worktree', 'add', '-q', '-b', 'feat', join(home, 'gwrepo--feat'));
  run('fish', ['-i', '-c', `cd ${home}/gwrepo--feat; echo n | gwd`]);
  assert.ok(existsSync(join(home, 'gwrepo--feat')));
  run('fish', ['-i', '-c', `cd ${home}/gwrepo--feat; echo y | gwd`]);
  assert.ok(!existsSync(join(home, 'gwrepo--feat')));
  assert.equal(git('branch', '--list', 'feat').stdout, '');
});

test('mise reads the tools and settings v2 gives it', () => {
  assert.equal(run('mise', ['settings', 'get', 'node.corepack']).stdout.trim(), 'false');
  assert.equal(run('mise', ['settings', 'get', 'upgrade.auto_prune']).stdout.trim(), 'false');
  const tools = readFileSync(join(home, '.config/mise/config.toml'), 'utf8');
  for (const tool of ['node = "24.21.0"', 'deno = "latest"', '"npm:cf" = "latest"']) assert.ok(tools.includes(tool), tool);
});

test('fish writes its history to the file dots sync reads', () => {
  const r = run('fish', ['-i', '-c', 'history append "echo marker-xyz"; history save']);
  assert.equal(r.status, 0, r.stderr);
  const hist = join(env.XDG_DATA_HOME, 'fish/fish_history');
  assert.match(readFileSync(hist, 'utf8'), /^- cmd: echo marker-xyz$/m);
  assert.deepEqual(files(join(env.XDG_DATA_HOME, 'fish')), ['fish_history']);
});

test('the prompt shows the directory\'s name, the git branch and a failed status', () => {
  const r = run('fish', ['-i', '-c', 'mkdir -p ~/code/proj; cd ~/code/proj; git init -q -b main; false; fish_prompt']);
  assert.equal(r.status, 0, r.stderr);
  // set_color's escapes aside, the words are the prompt.
  assert.equal(r.stdout.replace(/\x1b\[[0-9;:]*m|\x1b\(B/g, ''), 'proj main [1] › ');
  const ok = run('fish', ['-i', '-c', 'cd ~; true; fish_prompt']);
  assert.equal(ok.stdout.replace(/\x1b\[[0-9;:]*m|\x1b\(B/g, ''), '~ › ');
});

test('git has one excludes file under ~/.config/git and both accounts rewrite', () => {
  const ex = run('git', ['config', '--type=path', '--get-all', 'core.excludesFile']);
  assert.equal(ex.stdout, join(home, '.config/git/ignore') + '\n');
  const urls = run('git', ['config', '--get-regexp', '^url\\.']).stdout.split('\n');
  for (const line of [
    'url.git@github.com-lareys:lareysbd/.insteadof git@github.com:lareysbd/',
    'url.git@github.com-lareys:lareysbd/.insteadof https://github.com/lareysbd/',
    'url.git@github.com-lareys:lareysbd/.insteadof ssh://git@github.com/lareysbd/',
    'url.git@github.com:saifulapm/.insteadof https://github.com/saifulapm/',
    'url.git@github.com:saifulapm/.insteadof ssh://git@github.com/saifulapm/',
  ]) assert.ok(urls.includes(line), line);
});

// workflow install writes its hook stubs there, and they chain into each repo's own hooks.
test('every repo runs the hooks in ~/.config/git/hooks', () => {
  const r = run('git', ['config', '--type=path', '--get-all', 'core.hooksPath']);
  assert.equal(r.stdout, join(home, '.config/git/hooks') + '\n');
});

test('git pages through delta, and git dft diffs with difftastic', () => {
  assert.equal(run('git', ['config', '--global', 'core.pager']).stdout, 'delta\n');
  const repoDir = join(home, 'dft');
  mkdirSync(repoDir);
  const git = (...args) => spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { env, cwd: repoDir, encoding: 'utf8' });
  git('init', '-q');
  writeFileSync(join(repoDir, 'a.txt'), 'a\n');
  git('add', 'a.txt');
  git('commit', '-qm', 'one');
  writeFileSync(join(repoDir, 'a.txt'), 'a\nb\n');
  git('commit', '-qam', 'two');
  const r = git('dft', 'HEAD~1');
  assert.equal(r.status, 0, r.stderr);
  // difftastic heads each file with its name and the language it parsed.
  assert.match(r.stdout, /^a\.txt --- Text/m);
});

test('no config file hard-codes the home path', () => {
  const walk = (d) => readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(d, e.name)) : [join(d, e.name)]));
  const all = [...walk(fishDir), ...walk(gitDir)];
  assert.ok(all.length > 0);
  assert.deepEqual(all.filter((f) => readFileSync(f, 'utf8').includes('/home/saiful')), []);
});

test('the agent, pnpm and tunnel aliases run what v1 ran', () => {
  const want = {
    cx: 'claude --allow-dangerously-skip-permissions',
    pa: 'pi --approve',
    p: 'pnpm',
    pdev: 'pnpm run dev',
    dev: 'cloudflared tunnel --config ~/.cloudflared/config.dev.yaml run dev',
  };
  for (const [name, body] of Object.entries(want)) {
    const r = run('fish', ['-i', '-c', `functions ${name}`]);
    assert.ok(r.stdout.includes(body), `${name}: ${r.stdout}${r.stderr}`);
  }
});

// try draws its picker on /dev/tty, so it runs under python's pty for a terminal.
test('try clone puts a repo in ~/Tries and moves the shell into it', () => {
  const src = join(root, 'src.git');
  spawnSync('git', ['init', '-q', '--bare', src]);
  const fish = ['fish', '-i', '-c', `try clone file://${src} demo >/dev/null; pwd`];
  const r = spawnSync('python3', ['-c', 'import pty, sys; sys.exit(pty.spawn(sys.argv[1:]) >> 8)', ...fish], { env, cwd: home, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.equal(r.stdout.trim().split(/\r?\n/).at(-1), join(home, 'Tries/demo'));
});
