// A scratch mail store for bin/kak-mail: a real notmuch database, a fake msmtp that records each send, and an env built from nothing, so no test reads or writes the real mail.
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const repo = new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
export const me = 'me@x.test';

export function mailRig(t) {
  const M = mkdtempSync(join(tmpdir(), 'mail-rig-'));
  t.after(() => rmSync(M, { recursive: true, force: true }));
  const home = join(M, 'home');
  const bin = join(M, 'bin');
  const mail = join(M, 'Mail');
  const sent = join(M, 'sent');
  for (const d of [home, bin, sent, ...['INBOX', 'Sent Messages'].flatMap((f) => ['new', 'cur', 'tmp'].map((s) => join(mail, 'icloud', f, s)))]) mkdirSync(d, { recursive: true });
  writeFileSync(join(M, 'notmuch-config'), `[database]\npath=${mail}\n[user]\nname=Me\nprimary_email=${me}\n[new]\ntags=unread;inbox;new\n`);
  // msmtp -t reads the recipients from the message, so both argv and stdin are kept.
  writeFileSync(join(bin, 'msmtp'), `#!/bin/sh\nn=$(ls "${sent}" | grep -c '\\.args$')\nprintf '%s\\n' "$@" >"${sent}/$n.args"\ncat >"${sent}/$n.eml"\n`);
  chmodSync(join(bin, 'msmtp'), 0o755);
  const env = {
    PATH: `${bin}:${join(repo, 'bin')}:/usr/bin:/bin`,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_DATA_HOME: join(home, '.local/share'),
    XDG_STATE_HOME: join(home, '.local/state'),
    XDG_CACHE_HOME: join(home, '.cache'),
    XDG_RUNTIME_DIR: join(M, 'run'),
    NOTMUCH_CONFIG: join(M, 'notmuch-config'),
    HEY_MAIL_DB_DIR: join(home, '.local/share/hey-mail'),
    LANG: 'C.UTF-8',
  };
  const run = (cmd, args, opts = {}) => spawnSync(cmd, args, { env, encoding: 'utf8', ...opts });
  const notmuch = (...args) => {
    const r = run('notmuch', args);
    if (r.status !== 0) throw new Error(`notmuch ${args.join(' ')}: ${r.stderr}`);
    return r.stdout;
  };
  notmuch('new', '--quiet');
  let n = 0;
  // HEADERS is an object of header lines; the file lands in INBOX and notmuch indexes it.
  const deliver = (headers, body = 'hello\n') => {
    const h = { From: 'Ann <ann@people.test>', To: me, Subject: 'hi', Date: 'Sat, 14 Nov 2026 10:00:00 +0000', 'Message-ID': `<m${n}@x.test>`, ...headers };
    writeFileSync(join(mail, 'icloud/INBOX/new', `${n++}.eml`), Object.entries(h).map(([k, v]) => `${k}: ${v}\n`).join('') + '\n' + body);
    notmuch('new', '--quiet');
  };
  const kakMail = (...args) => run(join(repo, 'bin/kak-mail'), args);
  const sends = () => readdirSync(sent).filter((f) => f.endsWith('.args')).sort().map((f) => ({
    args: readFileSync(join(sent, f), 'utf8').trim().split('\n'),
    eml: readFileSync(join(sent, f.replace(/\.args$/, '.eml')), 'utf8'),
  }));
  const dbDir = env.HEY_MAIL_DB_DIR;
  const db = (name) => (existsSync(join(dbDir, name)) ? readFileSync(join(dbDir, name), 'utf8') : '');
  const setDb = (name, text) => { mkdirSync(dbDir, { recursive: true }); writeFileSync(join(dbDir, name), text); };
  return { M, env, mail, run, notmuch, deliver, kakMail, sends, db, setDb };
}
