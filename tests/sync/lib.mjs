// The only way tests/sync may run dots sync: each machine gets an env built from PATH and scratch dirs alone, so no run reaches the real HOME, rclone config or Dropbox.
import { spawn } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';

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

// opts.conf replaces the world's rclone.conf; opts.slow puts the slow rclone first on PATH.
export function machine(w, id, opts = {}) {
  const home = join(w.root, id);
  const env = {
    PATH: (opts.slow ? slowShim(w.root) + delimiter : '') + process.env.PATH,
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

// Runs `dots sync <args>` as machine m and resolves its exit code and output.
export function sync(m, args = []) {
  return new Promise((resolve, reject) => {
    const p = spawn(dots, ['sync'].concat(args), { env: checked(m.env) });
    let stdout = '';
    let stderr = '';
    p.stdout.on('data', (d) => (stdout += d));
    p.stderr.on('data', (d) => (stderr += d));
    p.on('error', reject);
    p.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}
