// dots dev against a fake systemctl that answers from a state file and logs every call, so the real user manager is never reached.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const dots = new URL('../../bin/dots', import.meta.url).pathname;

const SOCKETS = ['caddy-dev-http', 'caddy-dev-https', 'php-fpm-proxy', 'mysql84-proxy', 'postgres18-proxy', 'redis7-proxy', 'mailpit-smtp-proxy', 'mailpit-web-proxy'].map((s) => `${s}.socket`);

// opts.running: unit to started-at-epoch; sockets listen unless listed in opts.off.
function scratch(opts = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-services-')));
  const stubs = join(root, 'stubs');
  mkdirSync(stubs);
  const state = join(root, 'state');
  const active = { ...opts.running };
  for (const s of SOCKETS) if (!(opts.off || []).includes(s)) active[s] = 0;
  writeFileSync(state, Object.entries(active).map(([u, t]) => `${u} ${t}`).join('\n') + '\n');
  const log = join(root, 'calls.log');
  writeFileSync(log, '');
  writeFileSync(join(stubs, 'systemctl'), `#!/bin/sh
echo "$*" >>'${log}'
[ "$1" = --user ] && shift
case $1 in
  is-active) [ "$2" = -q ] && u=$3 || u=$2; grep -q "^$u " '${state}' ;;
  show) for u; do :; done; t=$(sed -n "s/^$u //p" '${state}'); date -d "@$t" '+%a %Y-%m-%d %H:%M:%S %Z' ;;
  stop) ;;
  *) exit 1 ;;
esac
`);
  chmodSync(join(stubs, 'systemctl'), 0o755);
  const run = (...args) => spawnSync(dots, ['dev', ...args], { encoding: 'utf8', env: { ...process.env, PATH: `${stubs}:${process.env.PATH}` } });
  return { run, calls: () => readFileSync(log, 'utf8').split('\n').filter(Boolean) };
}

test('with nothing active, six lines in order, each listening', () => {
  const r = scratch().run();
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, ['caddy-dev', 'php-fpm', 'mysql84', 'postgres18', 'redis7', 'mailpit'].map((n) => `${n} listening\n`).join(''));
});

test('an active main service reads running with its uptime, the rest listening', () => {
  const since = Math.floor(Date.now() / 1000) - 185;
  const r = scratch({ running: { 'mysql84.service': since } }).run();
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.split('\n').filter(Boolean);
  assert.equal(lines.length, 6);
  assert.equal(lines[2], 'mysql84 running 3m');
  assert.deepEqual(lines.filter((_, i) => i !== 2).map((l) => l.split(' ')[1]), Array(5).fill('listening'));
});

test('an uptime over an hour reads hours and minutes', () => {
  const since = Math.floor(Date.now() / 1000) - (72 * 60 + 10);
  const r = scratch({ running: { 'redis7.service': since } }).run();
  assert.match(r.stdout, /^redis7 running 1h 12m$/m);
});

test('a socket that is not listening reads off', () => {
  const r = scratch({ off: ['redis7-proxy.socket'] }).run();
  assert.match(r.stdout, /^redis7 off$/m);
});

test('stop mysql84 stops its proxy and itself, never a socket', () => {
  const s = scratch();
  const r = s.run('stop', 'mysql84');
  assert.equal(r.status, 0, r.stderr);
  const stops = s.calls().filter((c) => c.includes('stop'));
  assert.deepEqual(stops.map((c) => c.split(' ').slice(2).sort()), [['mysql84-proxy.service', 'mysql84.service']]);
  assert.ok(!stops.join('\n').includes('.socket'));
});

test('stop mailpit stops both proxies and the service', () => {
  const s = scratch();
  assert.equal(s.run('stop', 'mailpit').status, 0);
  const stops = s.calls().filter((c) => c.includes('stop')).flatMap((c) => c.split(' ').slice(2));
  assert.deepEqual(stops.sort(), ['mailpit-smtp-proxy.service', 'mailpit-web-proxy.service', 'mailpit.service']);
});

test('stop of an unknown name exits 2 and names it', () => {
  const s = scratch();
  const r = s.run('stop', 'nope');
  assert.equal(r.status, 2);
  assert.equal(r.stderr, 'dots dev: no service nope\n');
  assert.ok(!s.calls().some((c) => c.includes('stop')));
});

test('stop with no name prints usage and exits 2', () => {
  const r = scratch().run('stop');
  assert.equal(r.status, 2);
  assert.match(r.stderr, /usage: dots dev stop <name>/);
});
