// The kak config applied by chezmoi into a scratch home, then opened by the real kak with no UI.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
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
    .filter((l) => /error|could not load|no such command/i.test(l));
  assert.deepEqual(errors, []);
});

// ast-grep, usql, aspell, kak-popup and dedoc are not installed, so their plugins went; hop-kak and kak-ansi-filter are.
test('kak keeps hop and ansi, and has no plugin for a tool v2 does not install', () => {
  const tools = join(env.XDG_CONFIG_HOME, 'kak/autoload/tools');
  for (const f of ['ast-grep.kak', 'usql.kak', 'spell.kak', 'popup.kak']) assert.equal(existsSync(join(tools, f)), false, f);
  const out = join(root, 'kept.txt');
  const probe = (name) => `try %{ define-command ${name} nop; echo -to-file ${out}.${name} missing } catch %{ echo -to-file ${out}.${name} defined }`;
  const names = ['hop-kak', 'ansi-render-selection', 'docs', 'popup', 'spell'];
  const r = kak(`${names.map(probe).join('; ')}; try %{ dedoc } catch %{ echo -to-file ${out}.dedoc %val{error} }; quit!`);
  assert.equal(r.status, 0, r.stderr);
  const read = (name) => (existsSync(`${out}.${name}`) ? readFileSync(`${out}.${name}`, 'utf8') : 'not run');
  assert.deepEqual(Object.fromEntries(names.map((n) => [n, read(n)])), {
    'hop-kak': 'defined', 'ansi-render-selection': 'defined', docs: 'missing', popup: 'missing', spell: 'missing',
  });
  assert.match(read('dedoc'), /'dedoc': no such command$/);
});

test('kak loads the carried autoload, and nothing from kak-lsp', () => {
  const out = join(root, 'defined.txt');
  // define-command refuses a name that exists, so each catch marks a command the config defined.
  const probe = (name) => `try %{ define-command ${name} nop; echo -to-file ${out}.${name} missing } catch %{ echo -to-file ${out}.${name} defined }`;
  const names = ['url-open', 'lsp-enable-window', 'snippets-insert', 'emmet-expand'];
  const r = kak(`${names.map(probe).join('; ')}; quit!`);
  assert.equal(r.status, 0, r.stderr);
  const read = (name) => (existsSync(`${out}.${name}`) ? readFileSync(`${out}.${name}`, 'utf8') : 'not run');
  assert.deepEqual(Object.fromEntries(names.map((n) => [n, read(n)])), {
    'url-open': 'defined',
    'lsp-enable-window': 'missing',
    'snippets-insert': 'missing',
    'emmet-expand': 'missing',
  });
});

// Filetype hooks only run when a buffer of that type opens, so the first test cannot see them.
test('a PHP and a JavaScript buffer open with no error in the debug buffer', () => {
  const debug = join(root, 'debug-filetypes.txt');
  writeFileSync(join(root, 'a.php'), '<?php\n');
  writeFileSync(join(root, 'a.js'), 'let a;\n');
  const r = kak(`edit ${join(root, 'a.php')}; edit ${join(root, 'a.js')}; eval -buffer *debug* %{ write ${debug} }; quit!`);
  assert.equal(r.status, 0, r.stderr);
  const errors = readFileSync(debug, 'utf8')
    .split('\n')
    .filter((l) => /error|no such/i.test(l));
  assert.deepEqual(errors, []);
});

// v1 subscribed to 31 feeds; elfeed-kak reads them from the carried config, and the pin installs the binary.
test('elfeed-kak reads every feed v1 subscribed to', (t) => {
  const config = readFileSync(join(env.XDG_CONFIG_HOME, 'elfeed-kak/config.toml'), 'utf8');
  assert.equal(config.match(/^\[\[feed\]\]/gm)?.length, 31);
  const r = spawnSync('elfeed-kak', ['opml', 'export'], { env, encoding: 'utf8' });
  if (r.error?.code === 'ENOENT') return t.skip('elfeed-kak is not installed');
  assert.equal(r.stdout.match(/<outline /g)?.length, 31, r.stderr);
});

// A kak on the json ui draws what a terminal would, so the faces under a list's rows are read from what it sends.
function mailSession(t, expr) {
  const dir = mkdtempSync(join(tmpdir(), 'kak-mail-ui-'));
  const thread = (id, subject, tags) => ({ thread: id, timestamp: 1792500000, matched: 1, total: 1, authors: `Sender ${id}`, subject, tags });
  writeFileSync(join(dir, 'search.json'), JSON.stringify([
    thread('0001', 'First cursor row', ['inbox', 'unread']),
    thread('0002', 'Second read row', ['inbox']),
    thread('0003', 'Third unread row', ['inbox', 'unread']),
  ]));
  writeFileSync(join(dir, 'notmuch'), `#!/bin/sh\ncase "$1" in search) cat ${dir}/search.json ;; esac\n`, { mode: 0o755 });
  const kakEnv = { ...env, PATH: [dir, join(repo, 'bin'), env.PATH].join(':') };
  const p = spawn('kak', ['-ui', 'json', '-e', `${expr}`], { env: kakEnv });
  let buf = '';
  const msgs = [];
  p.stdout.on('data', (d) => {
    buf += d;
    const lines = buf.split('\n');
    buf = lines.pop();
    for (const l of lines) msgs.push(JSON.parse(l));
  });
  t.after(() => { p.kill(); rmSync(dir, { recursive: true, force: true }); });
  p.stdin.write('{"jsonrpc":"2.0","method":"resize","params":[12,100]}\n');
  const last = (method) => msgs.findLast((m) => m.method === method)?.params;
  const text = (atoms) => atoms.map((a) => a.contents).join('');
  return {
    dir,
    msgs,
    // Keys as kak names them, one array entry each.
    keys: (...keys) => p.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'keys', params: keys })}\n`),
    // The row of the last draw whose text holds WORD, as its atoms.
    row: (word) => last('draw')?.[0].find((atoms) => text(atoms).includes(word)),
    strip: () => text(last('draw_status')?.[3] ?? []),
    async until(fn, what) {
      for (let i = 0; i < 100; i++) {
        const v = fn();
        if (v) return v;
        await new Promise((r) => setTimeout(r, 50));
      }
      assert.fail(`kak never drew ${what}`);
    },
  };
}
const atomOf = (row, word) => row.find((a) => a.contents.includes(word));
const keysOf = (s) => [...s].map((c) => (c === ' ' ? '<space>' : c));

test('a kak-mail list draws its date, sender and subject in the Mail faces, unread bold, cursor row apart', async (t) => {
  const ui = mailSession(t, 'mail-box Imbox');
  const second = await ui.until(() => ui.row('Second read row'), 'the list');
  assert.equal(atomOf(second, 'Sender 0002').face.fg, 'rgb:2c4a9a');
  assert.equal(atomOf(second, 'Second read row').face.fg, 'rgb:1c1915');
  assert.deepEqual(atomOf(second, 'Second read row').face.attributes, []);
  const date = second.find((a) => /\d{4}-\d\d-\d\d|[A-Z][a-z]{2} \d\d/.test(a.contents));
  assert.equal(date.face.fg, 'rgb:575653');
  assert.ok(atomOf(ui.row('Third unread row'), 'Third unread row').face.attributes.includes('bold'));
  const cursor = atomOf(ui.row('First cursor row'), 'First cursor row').face;
  assert.equal(cursor.bg, 'rgb:1c1915');
  assert.equal(cursor.fg, 'rgb:faf6ec');
});

test('a kak-mail list ends in the key strip, and the cursor row follows the cursor', async (t) => {
  const ui = mailSession(t, 'mail-box Imbox');
  await ui.until(() => ui.row('Second read row'), 'the list');
  const want = '↵ OPEN · R REPLY · E ARCHIVE · S SCREENER · F FEED · ? HELP';
  await ui.until(() => ui.strip().includes(want), 'the strip');
  ui.keys('j', 'j');
  await ui.until(() => atomOf(ui.row('Third unread row'), 'Third unread row').face.bg === 'rgb:1c1915', 'the cursor on row 3');
  assert.ok(ui.strip().includes(want), ui.strip());
});

test('a theme switch recolours an open kak-mail list and its strip with no reopen', async (t) => {
  const ui = mailSession(t, 'mail-box Imbox');
  await ui.until(() => ui.row('Second read row'), 'the list');
  const render = (name) => assert.equal(spawnSync('node', [join(repo, 'shell/lib/theme-render.mjs'), name], { env, encoding: 'utf8' }).status, 0);
  t.after(() => render('paper'));
  render('artboard');
  ui.keys(...keysOf(':colorscheme dots'), '<ret>');
  await ui.until(() => atomOf(ui.row('Second read row') ?? [], 'Sender 0002')?.face.fg === 'rgb:3d5afe', 'the Artboard sender');
  await ui.until(() => ui.strip().includes('↵ open · r reply · e archive · s screener · f feed · ? help'), 'the Artboard strip');
});

test('? in a kak-mail list names the six strip keys, and e, s and f run the archive, screener and feed moves', async (t) => {
  const log = join(tmpdir(), `kak-mail-hey-${process.pid}`);
  t.after(() => rmSync(log, { force: true }));
  const ui = mailSession(t, `mail-box Imbox; define-command -override -hidden -params 1..2 mail-hey %{ nop %sh{ echo "$1" >> ${log} } }`);
  await ui.until(() => ui.row('Second read row'), 'the list');
  for (const k of ['e', 's', 'f', 'a']) ui.keys(k);
  await ui.until(() => existsSync(log) && readFileSync(log, 'utf8').split('\n').length > 4, 'the four moves');
  assert.deepEqual(readFileSync(log, 'utf8').trim().split('\n'), ['archive', 'unscreen', 'feed', 'archive']);
  ui.keys('?');
  const info = await ui.until(() => ui.msgs.findLast((m) => m.method === 'info_show')?.params, 'the help');
  const help = info[1].map((atoms) => atoms.map((a) => a.contents).join('')).join('\n');
  for (const line of [/^<ret>\s+read the thread/m, /^r .*reply/m, /^e \/ a\s+archive/m, /^s\s+screener/m, /^f\s+feed/m, /\?\s+this help/m]) assert.match(help, line);
});
