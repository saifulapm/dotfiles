// dots cutover on a scratch home holding a v1 checkout, v1's links and data, with systemctl replaced by a stub that keeps unit state in files.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const dots = new URL('../../bin/dots', import.meta.url).pathname;
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);

const v1Notes = (home, extra = []) => ({
  version: 2,
  notes: [
    { id: '0mt0a0001-aaaa', text: 'first note', path: '', done: false, updatedAt: '2026-09-04T00:00:00.000Z' },
    { id: '0mt0a0002-aaaa', text: '', path: join(home, '.local/state/qshell/notes/attachments/paste-1.png'), done: false, updatedAt: '2026-09-29T00:00:00.000Z' },
    { id: '0mt0a0003-aaaa', text: '', path: '', done: false, updatedAt: '2026-09-30T00:00:00.000Z', deletedAt: '2026-09-30T00:00:00.000Z' },
    ...extra,
  ],
});

const v1Goals = {
  version: 1,
  goals: [
    { id: 'g1', name: 'Ship', due: '2026-09-22T00:00:00.000Z', state: 'shipped', tasks: [{ id: 't1', text: 'a', done: true, updatedAt: '2026-09-21T00:00:00.000Z' }], createdAt: '2026-09-10T00:00:00.000Z', updatedAt: '2026-09-26T12:00:00.000Z', shippedAt: '2026-09-26T12:00:00.000Z' },
    { id: 'g2', name: 'Next', due: '2026-10-30T00:00:00.000Z', state: 'active', tasks: [], createdAt: '2026-10-01T00:00:00.000Z', updatedAt: '2026-10-02T00:00:00.000Z' },
  ],
};

const entry = (cmd, when) => `- cmd: ${cmd}\n  when: ${when}\n`;

function scratch() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-cutover-')));
  const home = join(root, 'home');
  const stubs = join(root, 'stubs');
  const units = join(root, 'units');
  const log = join(root, 'systemctl.log');
  mkdirSync(stubs);
  mkdirSync(units);
  for (const d of ['.dotfiles/home', '.config/fish/conf.d', '.config/fish/functions', '.config/fish/completions', '.config/systemd/user', '.config/qshell', '.local/state/qshell/notes/attachments', '.local/state/qshell/goals', '.local/share/fish', '.local/share/applications', 'repo']) mkdirSync(join(home, d), { recursive: true });

  writeFileSync(join(home, '.dotfiles/home/dot_gitconfig'), '[user]\n');
  writeFileSync(join(home, '.dotfiles/home/10-history.fish'), 'set -g fish_history x\n');
  writeFileSync(join(home, 'repo/aliases.fish'), '');
  symlinkSync(join(home, '.dotfiles/home/dot_gitconfig'), join(home, '.gitconfig'));
  symlinkSync(join(home, '.dotfiles/home/10-history.fish'), join(home, '.config/fish/conf.d/10-history.fish'));
  symlinkSync(join(home, 'repo/aliases.fish'), join(home, '.config/fish/conf.d/aliases.fish'));
  // v1's other fish files, desktop entries and unit files, as chezmoi's symlink mode left them; bt-agent.service has no v2 replacement and keeps running from ~/.dotfiles.
  for (const [file, at] of [['00-env.fish', '.config/fish/conf.d'], ['hdl.fish', '.config/fish/functions'], ['theme-set.fish', '.config/fish/completions'], ['webapp-x.desktop', '.local/share/applications'],
    ['qshell.service', '.config/systemd/user'], ['update-all.timer', '.config/systemd/user'], ['bt-agent.service', '.config/systemd/user']]) {
    writeFileSync(join(home, '.dotfiles/home', file), '');
    symlinkSync(join(home, '.dotfiles/home', file), join(home, at, file));
  }
  // dots install linked v2's imapnotify@ template, but v1's instance file of its mail watcher, pointing at v1's template, outranks it.
  writeFileSync(join(home, '.dotfiles/home/imapnotify@.service'), '');
  writeFileSync(join(home, 'repo/imapnotify@.service'), '');
  symlinkSync(join(home, 'repo/imapnotify@.service'), join(home, '.config/systemd/user/imapnotify@.service'));
  symlinkSync(join(home, '.dotfiles/home/imapnotify@.service'), join(home, '.config/systemd/user/imapnotify@icloud.service'));
  writeFileSync(join(home, 'repo/kak.desktop'), '');
  symlinkSync(join(home, 'repo/kak.desktop'), join(home, '.local/share/applications/kak.desktop'));

  writeFileSync(join(home, '.config/qshell/machine'), 'test-box\n');
  writeFileSync(join(home, '.local/state/qshell/notes/attachments/paste-1.png'), PNG);
  writeFileSync(join(home, '.local/state/qshell/notes/notes.json'), JSON.stringify(v1Notes(home)));
  writeFileSync(join(home, '.local/state/qshell/goals/goals.json'), JSON.stringify(v1Goals));
  writeFileSync(join(home, '.local/share/fish/test_box_history'), entry('ls', 100) + entry('make', 200));
  writeFileSync(join(home, '.local/share/fish/fish_history'), entry('ls', 100) + entry('v2 only', 300));

  // qshell.service is enabled and running, update-all.timer only enabled, v1's taildrop-receive.service, homepod-sink.service and havit-guard.service enabled and running, a static qshell-sync.service mid-run, and an unrelated v1 unit is enabled too.
  for (const f of ['qshell.service.enabled', 'qshell.service.active', 'update-all.timer.enabled', 'taildrop-receive.service.enabled', 'taildrop-receive.service.active', 'homepod-sink.service.enabled', 'homepod-sink.service.active', 'havit-guard.service.enabled', 'havit-guard.service.active', 'hub-local.service.enabled', 'hub-local.service.active', 'imapnotify@icloud.service.enabled', 'imapnotify@icloud.service.active']) writeFileSync(join(units, f), '');
  writeFileSync(join(units, 'qshell-sync.service.active'), 'activating');
  writeFileSync(
    join(stubs, 'systemctl'),
    `#!/bin/sh
echo "$*" >> ${log}
[ "$1" = --user ] || exit 1
case $2 in
  is-enabled) if [ -e ${units}/$3.enabled ]; then echo enabled; else echo static; fi ;;
  is-active) if [ -e ${units}/$3.active ]; then s=$(cat ${units}/$3.active); echo \${s:-active}; [ "\${s:-active}" = active ]; else echo inactive; exit 3; fi ;;
  disable) rm -f ${units}/$4.enabled ${units}/$4.active ;;
  stop) rm -f ${units}/$3.active ;;
  daemon-reload) ;;
  *) exit 1 ;;
esac
`,
  );
  chmodSync(join(stubs, 'systemctl'), 0o755);
  return { root, home, units, log };
}

const run = (s) =>
  spawnSync(dots, ['cutover'], {
    encoding: 'utf8',
    env: {
      PATH: join(s.root, 'stubs') + delimiter + process.env.PATH,
      HOME: s.home,
      XDG_CONFIG_HOME: join(s.home, '.config'),
      XDG_STATE_HOME: join(s.home, '.local/state'),
      XDG_DATA_HOME: join(s.home, '.local/share'),
      XDG_CACHE_HOME: join(s.home, '.cache'),
      DOTS_MACHINE: 'test',
    },
  });

const lastLine = (r) => r.stdout.trim().split('\n').at(-1);
const store = (s, unit) => JSON.parse(readFileSync(join(s.home, `.local/share/dots/${unit}/test.json`), 'utf8'));
// Every link under ~/.config and ~/.local/share that still points into ~/.dotfiles, relative to home.
const v1Links = (home) =>
  spawnSync('find', [join(home, '.config'), join(home, '.local/share'), '-type', 'l', '-lname', '*/.dotfiles/*'], { encoding: 'utf8' })
    .stdout.trim().split('\n').filter(Boolean).map((p) => p.slice(home.length + 1)).sort();
const calls = (s) => (existsSync(s.log) ? readFileSync(s.log, 'utf8').trim().split('\n') : []);

// Every path under the scratch home with its size and mtime, links by their target.
function snapshot(dir, out = []) {
  for (const name of readdirSync(dir).sort()) {
    const p = join(dir, name);
    const st = statSync(p, { throwIfNoEntry: false }) ?? {};
    out.push(`${p} ${st.size} ${st.mtimeMs}`);
    if (st.isDirectory?.()) snapshot(p, out);
  }
  return out;
}

test('cutover imports v1 notes, goals and history, stops the units v2 replaces, and prints one report line', () => {
  const s = scratch();
  const r = run(s);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(lastLine(r), 'notes: 2 imported · goals: 2 imported · history: 1 merged · v1 units: 7 stopped');

  const notes = store(s, 'notes').notes;
  assert.deepEqual(notes.filter((n) => !n.deleted).map((n) => n.id).sort(), ['0mt0a0001-aaaa', '0mt0a0002-aaaa']);
  assert.equal(notes.find((n) => n.id === '0mt0a0003-aaaa').deleted, true);
  const sha = createHash('sha256').update(PNG).digest('hex');
  assert.deepEqual(notes.find((n) => n.id === '0mt0a0002-aaaa').attachments, [{ sha256: sha, name: 'paste-1.png', mime: 'image/png', size: PNG.length }]);
  assert.deepEqual(readFileSync(join(s.home, `.local/share/dots/notes/attachments/${sha}.png`)), PNG);

  const goals = store(s, 'goals').goals;
  assert.deepEqual(goals.map((g) => [g.id, g.done]), [['g1', true], ['g2', false]]);
  assert.equal(goals.reduce((n, g) => n + g.tasks.length, 0), 1);

  assert.equal(readFileSync(join(s.home, '.local/share/fish/fish_history'), 'utf8'), entry('ls', 100) + entry('make', 200) + entry('v2 only', 300));
});

test('only the v1 units v2 replaces are stopped, and only the v1 links that outrank v2 are removed', () => {
  const s = scratch();
  assert.equal(run(s).status, 0);
  assert.deepEqual(calls(s).filter((c) => c.includes('disable')), ['--user disable --now qshell.service', '--user disable --now qshell-sync.service', '--user disable --now update-all.timer', '--user disable --now taildrop-receive.service', '--user disable --now homepod-sink.service', '--user disable --now havit-guard.service']);
  // v1's mail watcher only stops: disabling it would drop the wants link v2's instance of the same name starts from.
  assert.deepEqual(calls(s).filter((c) => /imapnotify|daemon-reload/.test(c)), ['--user stop imapnotify@icloud.service', '--user daemon-reload']);
  assert.deepEqual(readdirSync(s.units).sort(), ['hub-local.service.active', 'hub-local.service.enabled', 'imapnotify@icloud.service.enabled']);
  assert.equal(existsSync(join(s.home, '.gitconfig')), false);
  assert.equal(existsSync(join(s.home, '.config/fish/conf.d/10-history.fish')), false);
  assert.ok(existsSync(join(s.home, '.config/fish/conf.d/aliases.fish')), 'a link into the v2 repo stays');
  assert.ok(existsSync(join(s.home, '.local/share/applications/kak.desktop')), 'a desktop entry from the v2 repo stays');
  assert.deepEqual(v1Links(s.home), ['.config/systemd/user/bt-agent.service']);
  assert.ok(existsSync(join(s.home, '.dotfiles/home/dot_gitconfig')), '~/.dotfiles stays in place');
});

test('a ~/.gitconfig that is not v1s link is left alone', () => {
  const s = scratch();
  spawnSync('rm', [join(s.home, '.gitconfig')]);
  writeFileSync(join(s.home, '.gitconfig'), '[user]\n');
  assert.equal(run(s).status, 0);
  assert.equal(readFileSync(join(s.home, '.gitconfig'), 'utf8'), '[user]\n');
});

test('a second run imports nothing, stops nothing and changes no file', () => {
  const s = scratch();
  assert.equal(run(s).status, 0);
  const before = snapshot(s.root);
  const r = run(s);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(lastLine(r), 'notes: 0 imported · goals: 0 imported · history: 0 merged · v1 units: 0 stopped');
  assert.deepEqual(snapshot(s.root).filter((l) => !l.includes('systemctl.log')), before.filter((l) => !l.includes('systemctl.log')));
});

test('a note made in v1 after the first run comes in with the next one', () => {
  const s = scratch();
  assert.equal(run(s).status, 0);
  writeFileSync(join(s.home, '.local/state/qshell/notes/notes.json'), JSON.stringify(v1Notes(s.home, [{ id: '0mvaaaaaa-new1', text: 'later', path: '', done: false, updatedAt: '2026-10-19T00:00:00.000Z' }])));
  const r = run(s);
  assert.match(lastLine(r), /^notes: 1 imported · goals: 0 imported/);
  assert.ok(store(s, 'notes').notes.some((n) => n.id === '0mvaaaaaa-new1' && n.text === 'later'));
});

test('a machine without v1 data imports nothing and still succeeds', () => {
  const s = scratch();
  spawnSync('rm', ['-rf', join(s.home, '.local/state/qshell'), join(s.home, '.local/share/fish/test_box_history')]);
  const r = run(s);
  assert.equal(r.status, 0, r.stderr);
  assert.match(lastLine(r), /^notes: 0 imported · goals: 0 imported · history: 0 merged/);
});

test('a v1 notes file that does not parse fails the cutover by name and leaves the v2 store alone', () => {
  const s = scratch();
  writeFileSync(join(s.home, '.local/state/qshell/notes/notes.json'), '{');
  const r = run(s);
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /notes\.json/);
  assert.equal(existsSync(join(s.home, '.local/share/dots/notes/test.json')), false);
});
