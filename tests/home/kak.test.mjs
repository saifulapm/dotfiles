// The kak config applied by chezmoi into a scratch home, then opened by the real kak with no UI.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
// The scratch HOME hides ~/.local/bin and ~/.cargo/bin from a PATH that names them as ~, so both go in by their real paths.
const PATH = [join(process.env.HOME, '.local/bin'), join(process.env.HOME, '.cargo/bin'), process.env.PATH].join(':');
let root;
let env;

before(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'kak-test-')));
  const home = join(root, 'home');
  const run = join(root, 'run');
  mkdirSync(home);
  mkdirSync(run, { mode: 0o700 });
  env = {
    PATH,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_DATA_HOME: join(home, '.local/share'),
    XDG_STATE_HOME: join(home, '.local/state'),
    XDG_CACHE_HOME: join(home, '.cache'),
    XDG_RUNTIME_DIR: run,
  };
  const config = join(root, 'chezmoi.toml');
  writeFileSync(config, `sourceDir = "${repo}"\nmode = "symlink"\n\n[data]\n    machine = "test"\n`);
  const applied = spawnSync(
    'chezmoi',
    ['--config', config, '--source', repo, '--destination', home, 'apply', '--exclude', 'scripts'],
    { encoding: 'utf8', env },
  );
  assert.equal(applied.status, 0, applied.stderr);
  // The colorscheme file kakrc loads is the one dots theme renders.
  const theme = spawnSync('node', [join(repo, 'shell/lib/theme-render.mjs'), 'paper'], { encoding: 'utf8', env });
  assert.equal(theme.status, 0, theme.stderr);
});

function kak(commands) {
  return spawnSync('kak', ['-ui', 'dummy', '-e', commands], { encoding: 'utf8', env, timeout: 20000 });
}

test('kak opens with the carried config and the debug buffer holds no error', () => {
  const debug = join(root, 'debug.txt');
  const r = kak(`eval -buffer *debug* %{ write ${debug} }; quit!`);
  assert.equal(r.status, 0, r.stderr);
  assert.ok(existsSync(debug), 'kak wrote no debug buffer');
  const errors = readFileSync(debug, 'utf8')
    .split('\n')
    // kak's own kakrc sources each autoload file in a try and logs a failure as "could not load".
    .filter((l) => /error|could not load/i.test(l));
  assert.deepEqual(errors, []);
});

test('kak loads the carried autoload and the kak-lsp plugin', () => {
  const out = join(root, 'defined.txt');
  // define-command refuses a name that exists, so each catch marks a command the config defined.
  const probe = (name) => `try %{ define-command ${name} nop; echo -to-file ${out}.${name} missing } catch %{ echo -to-file ${out}.${name} defined }`;
  const r = kak(`${probe('url-open')}; ${probe('lsp-enable-window')}; quit!`);
  assert.equal(r.status, 0, r.stderr);
  const read = (name) => (existsSync(`${out}.${name}`) ? readFileSync(`${out}.${name}`, 'utf8') : 'not run');
  assert.deepEqual(
    { 'url-open': read('url-open'), 'lsp-enable-window': read('lsp-enable-window') },
    { 'url-open': 'defined', 'lsp-enable-window': 'defined' },
  );
});
