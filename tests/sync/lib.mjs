// The only way tests/sync may run dots sync, fish or age-keygen: each machine gets an env built from PATH and scratch dirs alone, so no run reaches the real HOME, rclone config or Dropbox.
import { spawn } from 'node:child_process';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, dirname, join } from 'node:path';

const dots = new URL('../../bin/dots', import.meta.url).pathname;
const SCRATCH = ['HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'RCLONE_CONFIG'];

// One alias remote in a fresh temp dir, shared by every machine made from it.
export function world() {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-sync-')));
  const remote = join(root, 'remote');
  mkdirSync(remote);
  const conf = join(root, 'rclone.conf');
  writeFileSync(conf, `[Dropbox]\ntype = alias\nremote = ${remote}\n`);
  return { root, remote, conf };
}

// A shim rclone that waits 0.3 s per call, so a round lasts long enough for a second run to meet its lock.
function slowShim(root) {
  const real = process.env.PATH.split(delimiter).map((d) => join(d, 'rclone')).find((p) => existsSync(p));
  const dir = join(root, 'shim');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'rclone'), `#!/bin/sh\nsleep 0.3\nexec ${real} "$@"\n`);
  chmodSync(join(dir, 'rclone'), 0o755);
  return dir;
}

// A shim rclone that, after any push of the ssh meta, puts another machine's meta over it, as if b pushed a moment later.
function racerShim(w) {
  const real = process.env.PATH.split(delimiter).map((d) => join(d, 'rclone')).find((p) => existsSync(p));
  const dir = join(w.root, 'racer');
  mkdirSync(dir, { recursive: true });
  const meta = join(w.remote, 'qshell-sync/ssh/ssh.meta.json');
  writeFileSync(join(dir, 'rclone'), `#!/bin/sh\n${real} "$@" || exit\ncase " $* " in *" copyto "*"/ssh.meta.json ") echo '{"hash":"f00","machine":"b","when":"later"}' > ${meta} ;; esac\n`);
  chmodSync(join(dir, 'rclone'), 0o755);
  return dir;
}

// opts.conf replaces the world's rclone.conf; opts.slow puts the slow rclone first on PATH; opts.racer the racing one.
export function machine(w, id, opts = {}) {
  const home = join(w.root, id);
  const env = {
    PATH: (opts.slow ? slowShim(w.root) + delimiter : '') + (opts.racer ? racerShim(w) + delimiter : '') + process.env.PATH,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_DATA_HOME: join(home, '.local/share'),
    XDG_STATE_HOME: join(home, '.local/state'),
    XDG_RUNTIME_DIR: join(home, 'run'),
    RCLONE_CONFIG: opts.conf ?? w.conf,
    DOTS_MACHINE: id,
  };
  for (const k of SCRATCH.slice(0, 5)) mkdirSync(env[k], { recursive: true });
  return { id, env, data: join(env.XDG_DATA_HOME, 'dots'), status: join(env.XDG_STATE_HOME, 'dots/sync.json') };
}

export function checked(env) {
  const tmp = realpathSync(tmpdir()) + '/';
  for (const k of SCRATCH) {
    if (!env[k] || !existsSync(env[k]) || !realpathSync(env[k]).startsWith(tmp)) throw new Error(`refusing ${k}=${env[k]}: not under ${tmp}`);
  }
  if (!env.DOTS_MACHINE) throw new Error('refusing a run without DOTS_MACHINE');
  return env;
}

export const sync = (m, args = []) => run(m, dots, ['sync'].concat(args));

// dots forget, run as machine m.
export const forget = (m, args) => run(m, dots, ['forget'].concat(args));

// The names in a tarball, listed as machine m.
export const tarList = (m, path) => run(m, 'tar', ['tzf', path]);

// What `history` prints in fish run as m, newest command first.
export const fishHistory = (m) => run(m, 'fish', ['-c', 'history']);

const bin = new URL('../../bin/', import.meta.url).pathname;

// A notmuch store in m's scratch home, found through $HOME/.notmuch-config; with opts.hooks, notmuch new runs the repo's post-new, beside a notify-send and msmtp that do nothing.
export function mailbox(m, opts = {}) {
  const mail = join(m.env.HOME, 'Mail');
  for (const s of ['new', 'cur', 'tmp']) mkdirSync(join(mail, 'icloud/INBOX', s), { recursive: true });
  let hooks = '';
  if (opts.hooks) {
    const dir = join(m.env.HOME, 'hooks');
    const stubs = join(m.env.HOME, 'stubs');
    mkdirSync(dir, { recursive: true });
    mkdirSync(stubs, { recursive: true });
    copyFileSync(new URL('../../home/dot_config/notmuch/hooks/executable_post-new', import.meta.url).pathname, join(dir, 'post-new'));
    chmodSync(join(dir, 'post-new'), 0o755);
    for (const tool of ['notify-send', 'msmtp']) {
      writeFileSync(join(stubs, tool), '#!/bin/sh\nexit 0\n');
      chmodSync(join(stubs, tool), 0o755);
    }
    m.env.PATH = stubs + delimiter + m.env.PATH;
    hooks = `hook_dir=${dir}\n`;
  }
  writeFileSync(join(m.env.HOME, '.notmuch-config'), `[database]\npath=${mail}\n${hooks}[user]\nname=Me\nprimary_email=me@x.test\n[new]\ntags=unread;inbox;new\n`);
  m.mail = mail;
  m.hey = join(m.env.XDG_DATA_HOME, 'hey-mail');
  mkdirSync(m.hey, { recursive: true });
  return run(m, 'notmuch', ['new', '--quiet']);
}

// Puts one mail from FROM with Message-ID ID in m's INBOX, a reply to REPLYTO when given, and indexes it.
export function deliver(m, from, id, replyTo) {
  const thread = replyTo ? `In-Reply-To: <${replyTo}>\nReferences: <${replyTo}>\n` : '';
  writeFileSync(join(m.mail, 'icloud/INBOX/new', id.replace(/[^\w.-]/g, '_') + '.eml'), `From: ${from}\nTo: me@x.test\nSubject: hi\nMessage-ID: <${id}>\n${thread}\nhello\n`);
  return run(m, 'notmuch', ['new', '--quiet']);
}

export const notmuch = (m, args) => run(m, 'notmuch', args);

// Kakoune's mail commands, run as m.
export const kakMail = (m, args) => run(m, bin + 'kak-mail', args);

// The mail command, run as m.
export const mail = (m, args) => run(m, bin + 'mail', args);

// One mail-sync run as m: fetch, index, then file into IMAP folders, under its lock.
export const mailSync = (m) => run(m, bin + 'mail-sync', ['--quiet']);

// The age identity the ssh unit reads, made for m, or copied from another machine so both open one blob.
export async function identity(m, from) {
  const path = join(m.env.XDG_CONFIG_HOME, 'chezmoi/key.txt');
  mkdirSync(dirname(path), { recursive: true });
  if (from) return copyFileSync(join(from.env.XDG_CONFIG_HOME, 'chezmoi/key.txt'), path);
  const r = await run(m, 'age-keygen', ['-o', path]);
  if (r.code !== 0) throw new Error('age-keygen: ' + r.stderr);
}

// Gives m the iCloud mail entry the reminders push reads, as a pass that prints it and the .gpg file pass would decrypt, and points the push at the fake iCloud.
export function icloudEntry(m, fake, name = 'me') {
  const store = join(m.env.HOME, '.password-store/email/icloud');
  mkdirSync(store, { recursive: true });
  writeFileSync(join(store, name + '.gpg'), '');
  const dir = join(m.env.HOME, 'pass-bin');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'pass'), `#!/bin/sh\n[ "$1 $2" = "show email/icloud/${name}" ] || exit 1\nprintf 'app-pass-1\\ntype: icloud\\nuser: me@x.test\\nimap: imap.mail.me.com\\n'\n`);
  chmodSync(join(dir, 'pass'), 0o755);
  m.env.PATH = dir + delimiter + m.env.PATH;
  m.env.DOTS_CALDAV_URL = fake.url;
}

// Every process's argv as ps prints it, read as machine m.
export const processArgs = (m) => run(m, 'ps', ['-eo', 'args']);

// The one place a sync test starts a process: as machine m, in its scratch env.
const start = (m, cmd, args) => spawn(cmd, args, { env: checked(m.env) });

// Runs cmd with args as machine m and resolves its exit code and output.
function run(m, cmd, args) {
  return new Promise((resolve, reject) => {
    const p = start(m, cmd, args);
    let stdout = '';
    let stderr = '';
    p.stdout.on('data', (d) => (stdout += d));
    p.stderr.on('data', (d) => (stderr += d));
    p.on('error', reject);
    p.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

// Holds m's sync lock from another process for the given seconds; resolves once it is held, with a promise that resolves when it is let go.
export function holdLock(m, seconds) {
  const dir = join(m.env.XDG_STATE_HOME, 'dots');
  mkdirSync(dir, { recursive: true });
  return new Promise((resolve, reject) => {
    const p = start(m, 'flock', [join(dir, 'dots-sync.lock'), '-c', `echo held; sleep ${seconds}`]);
    const freed = new Promise((done) => p.on('close', done));
    p.on('error', reject);
    p.stdout.once('data', () => resolve({ freed }));
  });
}
