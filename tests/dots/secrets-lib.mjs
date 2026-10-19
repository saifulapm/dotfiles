// The only way tests/dots/secrets runs dots secrets, gpg, pass or age-keygen: every env is built from PATH and scratch dirs alone, so no run reaches the real key, ~/.ssh, ~/.gnupg, password store, rclone or gh config.
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const dots = new URL('../../bin/dots', import.meta.url).pathname;
const SCRATCH = ['HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'RCLONE_CONFIG', 'GNUPGHOME', 'PASSWORD_STORE_DIR', 'GH_CONFIG_DIR'];
// A dead proxy, so anything that tries the network fails at once instead of reaching it.
const OFFLINE = 'http://127.0.0.1:9';

export function checked(env) {
  const tmp = realpathSync(tmpdir()) + '/';
  for (const k of SCRATCH) {
    if (!env[k] || !resolve(env[k]).startsWith(tmp)) throw new Error(`refusing ${k}=${env[k]}: not under ${tmp}`);
  }
  return env;
}

// A scratch home under root whose rclone config holds conf; the password store and gh config are left for dots secrets to make.
export function home(root, id, conf) {
  const h = join(root, id);
  const env = {
    PATH: process.env.PATH,
    HOME: h,
    XDG_CONFIG_HOME: join(h, '.config'),
    XDG_DATA_HOME: join(h, '.local/share'),
    XDG_STATE_HOME: join(h, '.local/state'),
    XDG_RUNTIME_DIR: join(root, id + '-run'),
    RCLONE_CONFIG: join(h, '.config/rclone/rclone.conf'),
    GNUPGHOME: join(h, '.gnupg'),
    PASSWORD_STORE_DIR: join(h, '.password-store'),
    GH_CONFIG_DIR: join(h, '.config/gh'),
    DOTS_MACHINE: id,
    GH_NO_UPDATE_NOTIFIER: '1',
    HTTPS_PROXY: OFFLINE,
    HTTP_PROXY: OFFLINE,
    ALL_PROXY: OFFLINE,
    GIT_AUTHOR_NAME: 'test',
    GIT_AUTHOR_EMAIL: 'test@example.invalid',
    GIT_COMMITTER_NAME: 'test',
    GIT_COMMITTER_EMAIL: 'test@example.invalid',
  };
  for (const k of ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR']) mkdirSync(env[k], { recursive: true, mode: 0o700 });
  mkdirSync(env.GNUPGHOME, { mode: 0o700 });
  mkdirSync(join(env.XDG_CONFIG_HOME, 'rclone'));
  writeFileSync(env.RCLONE_CONFIG, conf);
  return env;
}

export const scratch = () => realpathSync(mkdtempSync(join(tmpdir(), 'dots-secrets-')));

export const secrets = (env) => run(env, dots, ['secrets']);

// Runs cmd with args in env and resolves its exit code and output; input, when given, goes to stdin.
export function run(env, cmd, args, input) {
  return new Promise((done, reject) => {
    // Without input stdin is /dev/null, as a pipe to a process that exits unread fails with EPIPE.
    const p = spawn(cmd, args, { env: checked(env), stdio: [input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    p.stdout.on('data', (d) => (stdout += d));
    p.stderr.on('data', (d) => (stderr += d));
    p.on('error', reject);
    p.on('close', (code) => done({ code, stdout, stderr }));
    if (input !== undefined) p.stdin.end(input);
  });
}

// Like run, but throws unless cmd exits 0, and resolves its stdout.
export async function must(env, cmd, args, input) {
  const r = await run(env, cmd, args, input);
  if (r.code !== 0) throw new Error(`${cmd} ${args.join(' ')} exited ${r.code}: ${r.stderr}`);
  return r.stdout;
}
