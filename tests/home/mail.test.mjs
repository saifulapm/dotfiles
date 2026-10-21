// The mail configs render only where the chezmoi age key exists: a keyless apply writes none and still exits 0, a keyed one writes them all.
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
const scripts = ['bin/mail-sync', 'bin/hey-folder-sync', 'bin/mail-open', 'bin/imapnotify-wait', 'home/dot_config/notmuch/hooks/executable_post-new'];
const address = 'test@example.com';

let root;

const run = (cmd, args, opts = {}) => spawnSync(cmd, args, { encoding: 'utf8', ...opts });
const has = (tool) => run('sh', ['-c', `command -v ${tool}`]).status === 0;

const scratchHome = (name) => {
  const home = join(root, name);
  mkdirSync(join(home, '.config/chezmoi'), { recursive: true });
  return home;
};

// The scratch config comes from the repo's own config template, so its age block is what the apply uses.
function apply(home, source) {
  const env = { PATH: process.env.PATH, HOME: home, XDG_CONFIG_HOME: join(home, '.config') };
  const config = `${home}.toml`;
  const init = run('chezmoi', ['init', '--source', repo, '--config', config, '--destination', home, '--promptString', 'machine=test'], { env });
  assert.equal(init.status, 0, init.stderr);
  return run('chezmoi', ['--config', config, '--source', source, '--destination', home, 'apply', '--exclude', 'scripts'], { env });
}

let keyless, keyed, porcelainBefore, porcelainAfter;

before(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'mail-')));
  porcelainBefore = run('git', ['-C', repo, 'status', '--porcelain']).stdout;

  keyless = { home: scratchHome('keyless') };
  keyless.result = apply(keyless.home, join(repo, 'home'));

  const src = join(root, 'src');
  cpSync(join(repo, 'home'), src, { recursive: true });
  keyed = { home: scratchHome('keyed') };
  const key = join(keyed.home, '.config/chezmoi/key.txt');
  assert.equal(run('age-keygen', ['-o', key]).status, 0);
  const recipient = run('age-keygen', ['-y', key]).stdout.trim();
  const plain = join(root, 'identities.toml');
  writeFileSync(plain, `primary = "${address}"\nothers = ["a@example.org", "b@example.net"]\n`);
  const enc = run('age', ['-a', '-r', recipient, '-o', join(src, '.chezmoitemplates/mail-identities.toml.age'), plain]);
  assert.equal(enc.status, 0, enc.stderr);
  keyed.result = apply(keyed.home, src);

  porcelainAfter = run('git', ['-C', repo, 'status', '--porcelain']).stdout;
});

after(() => rmSync(root, { recursive: true, force: true }));

test('a keyless apply exits 0 and writes no mail config', () => {
  assert.equal(keyless.result.status, 0, keyless.result.stderr);
  for (const f of ['.mbsyncrc', '.msmtprc', '.config/notmuch/default/config', '.config/imapnotify/icloud.yaml']) {
    assert.equal(existsSync(join(keyless.home, f)), false, f);
  }
});

test('the mail-sync service and timer are in place and both wait for ~/.mbsyncrc', () => {
  for (const unit of ['mail-sync.service', 'mail-sync.timer']) {
    const text = readFileSync(join(keyless.home, '.config/systemd/user', unit), 'utf8');
    assert.match(text, /^ConditionPathExists=%h\/\.mbsyncrc$/m, unit);
  }
});

test('niri starts the mail-sync timer at login', () => {
  const niri = readFileSync(join(keyless.home, '.config/niri/config.kdl'), 'utf8');
  assert.match(niri, /^spawn-at-startup "systemctl" "--user" "start" "mail-sync\.timer"$/m);
});

test('a keyed apply writes all three configs, private, naming the identities', () => {
  assert.equal(keyed.result.status, 0, keyed.result.stderr);
  assert.equal(keyed.result.stderr, '');
  const mbsyncrc = join(keyed.home, '.mbsyncrc');
  assert.equal(statSync(mbsyncrc).mode & 0o777, 0o600);
  assert.match(readFileSync(mbsyncrc, 'utf8'), /^User test@example\.com$/m);
  const msmtprc = join(keyed.home, '.msmtprc');
  assert.equal(statSync(msmtprc).mode & 0o777, 0o600);
  assert.match(readFileSync(msmtprc, 'utf8'), /^from\s+test@example\.com$/m);
  const notmuch = readFileSync(join(keyed.home, '.config/notmuch/default/config'), 'utf8');
  assert.match(notmuch, /^primary_email=test@example\.com$/m);
  assert.match(notmuch, /^other_email=a@example\.org;b@example\.net$/m);
});

test('neither apply changes the repo checkout', () => {
  assert.equal(porcelainAfter, porcelainBefore);
});

test('every carried script parses', () => {
  for (const s of scripts) {
    const r = run('bash', ['-n', join(repo, s)]);
    assert.equal(r.status, 0, `${s}: ${r.stderr}`);
  }
});

test('msmtp reads the rendered config', { skip: !has('msmtp') && 'msmtp is not installed' }, () => {
  const r = run('msmtp', ['-C', join(keyed.home, '.msmtprc'), '-a', 'icloud', '--passwordeval=echo stub', '-P'], { env: { PATH: process.env.PATH, HOME: keyed.home } });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /^host = smtp\.mail\.me\.com$/m);
});

test('notmuch reads the rendered config', { skip: !has('notmuch') && 'notmuch is not installed' }, () => {
  const config = join(keyed.home, '.config/notmuch/default/config');
  const r = run('notmuch', ['config', 'get', 'user.primary_email'], { env: { PATH: process.env.PATH, HOME: keyed.home, NOTMUCH_CONFIG: config } });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, `${address}\n`);
});

test('imapnotify@icloud starts with the session, waits for an unlocked agent, and stays off without its yaml', () => {
  const units = join(keyless.home, '.config/systemd/user');
  const text = readFileSync(join(units, 'imapnotify@.service'), 'utf8');
  assert.match(text, /^ConditionPathExists=%h\/\.config\/imapnotify\/%i\.yaml$/m);
  assert.match(text, /^ExecStartPre=%h\/Codes\/dotfiles\/bin\/imapnotify-wait %h\/\.config\/imapnotify\/%i\.yaml$/m);
  assert.match(text, /^TimeoutStartSec=infinity$/m);
  assert.match(text, /^Environment="PASSWORD_STORE_GPG_OPTS=--pinentry-mode=error"$/m);
  assert.match(text, /^ExecStart=%h\/\.local\/share\/mise\/shims\/goimapnotify -conf %h\/\.config\/imapnotify\/%i\.yaml$/m);
  assert.match(text, /^StartLimitBurst=5$/m);
  const link = join(units, 'graphical-session.target.wants/imapnotify@icloud.service');
  assert.ok(lstatSync(link).isSymbolicLink());
  assert.equal(readlinkSync(link), '../imapnotify@.service');
});

test('a keyed apply writes the imapnotify yaml for the primary address, syncing on new mail', () => {
  const yaml = readFileSync(join(keyed.home, '.config/imapnotify/icloud.yaml'), 'utf8');
  assert.match(yaml, /^\s+username: test@example\.com$/m);
  assert.match(yaml, /^\s+passwordCMD: "pass email\/icloud\/test \| head -n1"$/m);
  assert.match(yaml, new RegExp(`^\\s+onNewMail: "${keyed.home}/Codes/dotfiles/bin/mail-sync --quiet"$`, 'm'));
});

test('gpg-agent keeps a passphrase for 400 days and asks for it through dots-pinentry', () => {
  const text = readFileSync(join(keyless.home, '.gnupg/gpg-agent.conf'), 'utf8');
  assert.match(text, /^default-cache-ttl 34560000$/m);
  assert.match(text, /^max-cache-ttl 34560000$/m);
  assert.match(text, new RegExp(`^pinentry-program ${keyless.home}/Codes/dotfiles/bin/dots-pinentry$`, 'm'));
});

// A fake pass stands in for the store: it fails as gpg does on a locked key until its Nth call, so the wait is seen to retry and then stop.
function fakePass(dir, succeedOn) {
  mkdirSync(dir, { recursive: true });
  const pass = join(dir, 'pass');
  writeFileSync(pass, `#!/bin/bash
n=$(( $(cat "${dir}/calls" 2>/dev/null || echo 0) + 1 ))
echo $n > "${dir}/calls"
echo "$PASSWORD_STORE_GPG_OPTS|$*" >> "${dir}/log"
[ $n -ge ${succeedOn} ] || { echo "gpg: decryption failed: No pinentry" >&2; exit 2; }
echo hunter2
echo "host: imap.mail.me.com"
`);
  chmodSync(pass, 0o755);
  const yaml = join(dir, 'icloud.yaml');
  writeFileSync(yaml, 'configurations:\n    - host: imap.mail.me.com\n      passwordCMD: "pass email/icloud/test | head -n1"\n');
  return yaml;
}

const wait = (dir, yaml, timeout) =>
  run(join(repo, 'bin/imapnotify-wait'), [yaml], {
    env: { PATH: `${dir}:/usr/bin:/bin`, HOME: dir, IMAPNOTIFY_WAIT_SECONDS: '0.1' },
    timeout,
  });

test('imapnotify-wait returns once the password decrypts without a prompt, and prints nothing', () => {
  const dir = join(root, 'wait-ok');
  const r = wait(dir, fakePass(dir, 3), 10000);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, '');
  assert.deepEqual(readFileSync(join(dir, 'log'), 'utf8').trim().split('\n'), [
    '--pinentry-mode=error|email/icloud/test',
    '--pinentry-mode=error|email/icloud/test',
    '--pinentry-mode=error|email/icloud/test',
  ]);
});

test('imapnotify-wait keeps waiting while the agent is locked', () => {
  const dir = join(root, 'wait-locked');
  const r = wait(dir, fakePass(dir, 1000), 1500);
  assert.equal(r.signal, 'SIGTERM');
  assert.equal(r.stdout, '');
  assert.ok(Number(readFileSync(join(dir, 'calls'), 'utf8')) >= 3);
});

test('kak loads mail.kak with the carried config and no error', () => {
  const home = keyless.home;
  const runDir = join(root, 'kak-run');
  mkdirSync(runDir, { mode: 0o700 });
  // The scratch HOME hides ~/.local/bin, where the kak pin installs, so it goes in by its real path, after this checkout's bin/.
  const env = {
    PATH: [join(repo, 'bin'), join(process.env.HOME, '.local/bin'), process.env.PATH].join(':'),
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_DATA_HOME: join(home, '.local/share'),
    XDG_STATE_HOME: join(home, '.local/state'),
    XDG_CACHE_HOME: join(home, '.cache'),
    XDG_RUNTIME_DIR: runDir,
  };
  const theme = run('node', [join(repo, 'shell/lib/theme-render.mjs'), 'paper'], { env });
  assert.equal(theme.status, 0, theme.stderr);
  const out = join(root, 'kak-mail');
  // define-command refuses a name that exists, so each catch marks a command mail.kak defined.
  const names = ['mail', 'mail-sync', 'mail-compose', 'mail-box'];
  const probe = (name) => `try %{ define-command ${name} nop; echo -to-file ${out}.${name} missing } catch %{ echo -to-file ${out}.${name} defined }`;
  const r = run('kak', ['-ui', 'dummy', '-e', `${names.map(probe).join('; ')}; eval -buffer *debug* %{ write ${out}.debug }; quit!`], { env, timeout: 20000 });
  assert.equal(r.status, 0, r.stderr);
  const read = (name) => (existsSync(`${out}.${name}`) ? readFileSync(`${out}.${name}`, 'utf8') : 'not run');
  assert.deepEqual(Object.fromEntries(names.map((n) => [n, read(n)])), Object.fromEntries(names.map((n) => [n, 'defined'])));
  const errors = readFileSync(`${out}.debug`, 'utf8').split('\n').filter((l) => /error|could not load/i.test(l));
  assert.deepEqual(errors, []);
});

// A sender writes From and Subject, so a newline there split a list row (row i then opened message i+1) and printed a fake header; U+202E reordered the text after it.
test('kak-mail keeps a forged From and Subject on one line, without bidi controls', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'kak-mail-forged-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const evil = 'line1\nFrom: spoof@x.test\rline3\x1b[31mred ‮gpj.exe⁦';
  const msg = { id: 'a@x', match: true, timestamp: 1792500000, tags: ['inbox'], headers: { From: `Evil\nFrom: spoof@x.test <e@x.test>`, To: 'me@x.test', Date: 'Tue, 20 Oct 2026 14:00:00 +0000', Subject: evil }, body: [{ id: 1, 'content-type': 'text/plain', content: 'body\n' }] };
  const thread = { thread: '0001', timestamp: 1792500000, matched: 1, total: 1, authors: 'Evil\nFrom: spoof ‮exe', subject: evil, tags: ['inbox'] };
  const show = JSON.stringify([[[msg, []]]]);
  writeFileSync(join(dir, 'show.json'), show);
  writeFileSync(join(dir, 'search.json'), JSON.stringify([thread]));
  writeFileSync(join(dir, 'notmuch'), `#!/bin/sh\ncase "$1" in show) cat ${dir}/show.json ;; search) cat ${dir}/search.json ;; esac\n`, { mode: 0o755 });
  const env = { ...process.env, PATH: `${dir}:${process.env.PATH}`, HOME: dir };
  const bad = /[\x00-\x08\x0b-\x1f\x7f‎‏‪-‮⁦-⁩]/;
  for (const args of [['list', '--out', join(dir, 'list'), 'tag:inbox'], ['list', '--out', join(dir, 'flat'), '--unthreaded', 'tag:inbox']]) {
    const r = spawnSync(join(repo, 'bin/kak-mail'), args, { env, encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    const rows = readFileSync(args[2], 'utf8').replace(/\n$/, '').split('\n');
    assert.equal(rows.length, 1, rows.join('|'));
    assert.doesNotMatch(rows[0], bad);
  }
  const r = spawnSync(join(repo, 'bin/kak-mail'), ['show', '--out', join(dir, 'thread'), 'id:a@x'], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  const lines = readFileSync(join(dir, 'thread'), 'utf8').split('\n');
  assert.equal(lines.filter((l) => l.startsWith('From:')).length, 1, lines.join('|'));
  assert.equal(lines.filter((l) => l.startsWith('Subject:')).length, 1);
  assert.ok(!lines.some((l) => bad.test(l)), lines.join('|'));
});
