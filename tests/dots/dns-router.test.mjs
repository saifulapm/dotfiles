// dots-dns-router against a stub ssh that plays the router and a stub curl that serves the lists, on a scratch HOME.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { crc32 } from 'node:zlib';

const bin = new URL('../../bin/dots-dns-router', import.meta.url).pathname;
const files = new URL('../../system/openwrt/dns-shield/', import.meta.url).pathname;

// The stub ssh logs its argv, keeps what it is sent, and answers the few commands the script sends from files in the ctl dir.
const SSH = `
const fs = require('node:fs');
const ctl = process.env.STUB_CTL;
const args = process.argv.slice(2);
const cmd = args[args.length - 1];
fs.appendFileSync(ctl + '/ssh.log', JSON.stringify(args) + '\\n');
if (/tar xzf - -C/.test(cmd)) { fs.writeFileSync(ctl + '/payload.tgz', fs.readFileSync(0)); process.exit(0); }
if (/^test ! -e/.test(cmd)) process.exit(fs.existsSync(ctl + '/installed') ? 1 : 0);
if (/sysupgrade -b/.test(cmd)) { process.stdout.write(fs.readFileSync(ctl + '/router-backup.tgz')); process.exit(0); }
if (/cat .*run\\.log/.test(cmd)) {
  // run.log.1, when there, is what the log held before the script finished.
  if (fs.existsSync(ctl + '/run.log.1')) { process.stdout.write(fs.readFileSync(ctl + '/run.log.1', 'utf8')); fs.rmSync(ctl + '/run.log.1'); process.exit(0); }
  process.stdout.write(fs.readFileSync(ctl + '/run.log', 'utf8'));
  process.exit(0);
}
process.exit(0);
`;

// The stub curl writes the file named after the URL's last path part to -o.
const CURL = `
const fs = require('node:fs');
const args = process.argv.slice(2);
const out = args[args.indexOf('-o') + 1];
const url = args[args.length - 1];
fs.appendFileSync(process.env.STUB_CTL + '/curl.log', url + '\\n');
fs.copyFileSync(process.env.STUB_CTL + '/' + url.split('/').pop(), out);
`;

// A zip with one stored entry, which is all unzip -p needs.
function zip(name, data) {
  const n = Buffer.from(name);
  const crc = crc32(data) >>> 0;
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(20, 4);
  local.writeUInt32LE(crc, 14);
  local.writeUInt32LE(data.length, 18);
  local.writeUInt32LE(data.length, 22);
  local.writeUInt16LE(n.length, 26);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0);
  central.writeUInt16LE(20, 4);
  central.writeUInt16LE(20, 6);
  central.writeUInt32LE(crc, 16);
  central.writeUInt32LE(data.length, 20);
  central.writeUInt32LE(data.length, 24);
  central.writeUInt16LE(n.length, 28);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(1, 8);
  end.writeUInt16LE(1, 10);
  end.writeUInt32LE(46 + n.length, 12);
  end.writeUInt32LE(30 + n.length + data.length, 16);
  return Buffer.concat([local, n, data, central, n, end]);
}

// 2400 gambling names, of which the top list ranks the even ones, plus sites that are not gambling.
function lists(ctl) {
  const names = Array.from({ length: 2400 }, (_, i) => `bet${i}.example`);
  writeFileSync(join(ctl, 'gambling.mini.txt'), '# Title: test\n' + names.map((d) => `local=/${d}/`).join('\n') + '\n');
  const ranked = names.filter((_, i) => i % 2 === 0).concat(['wikipedia.org', 'khanacademy.org']);
  writeFileSync(join(ctl, 'top-1m.csv.zip'), zip('top-1m.csv', Buffer.from(ranked.map((d, i) => `${i + 1},${d}\r\n`).join(''))));
  return ranked.filter((d) => d.startsWith('bet'));
}

function backupTgz(dir) {
  const src = join(dir, 'backup-src');
  mkdirSync(join(src, 'etc', 'config'), { recursive: true });
  for (const f of ['dhcp', 'firewall', 'https-dns-proxy']) writeFileSync(join(src, 'etc', 'config', f), `config ${f}\n`);
  const out = join(dir, 'router-backup.tgz');
  execFileSync('tar', ['czf', out, '-C', src, 'etc/config/dhcp', 'etc/config/firewall', 'etc/config/https-dns-proxy']);
  return out;
}

function scratch(t, { backup = true, jump = 'nuc' } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'dns-router-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, 'home');
  const ctl = join(root, 'ctl');
  const stubBin = join(root, 'bin');
  for (const d of [ctl, stubBin, join(home, '.config', 'dns-helper')]) mkdirSync(d, { recursive: true });
  writeFileSync(join(stubBin, 'ssh'), `#!${process.execPath}\n${SSH}`, { mode: 0o755 });
  writeFileSync(join(stubBin, 'curl'), `#!${process.execPath}\n${CURL}`, { mode: 0o755 });
  writeFileSync(join(home, '.config', 'dns-helper', 'router.env'), `WIFI_PSK='secret-psk'\nSSH_KEY=$HOME/.ssh/router\n${jump ? `ROUTER_JUMP=${jump}\n` : ''}`);
  const tgz = backupTgz(ctl);
  const state = join(home, '.local', 'state', 'dns-helper');
  if (backup) {
    mkdirSync(join(state, 'router-backup-2026-10-22'), { recursive: true });
    writeFileSync(join(state, 'router-backup-2026-10-22', 'sysupgrade-backup.tar.gz'), readFileSync(tgz));
  }
  const env = {
    HOME: home,
    XDG_CONFIG_HOME: join(root, 'config'),
    XDG_STATE_HOME: join(root, 'state'),
    XDG_CACHE_HOME: join(root, 'cache'),
    XDG_DATA_HOME: join(root, 'data'),
    TMPDIR: process.env.TMPDIR || tmpdir(),
    PATH: `${stubBin}:/usr/bin:/bin`,
    STUB_CTL: ctl,
    DOTS_DNS_ROUTER_POLL: '0.05',
  };
  return { root, home, ctl, state, env, stubBin, tgz };
}

const run = (s, ...args) => spawnSync(bin, args, { env: s.env, encoding: 'utf8', timeout: 20000 });
const sshCalls = (s) => (existsSync(join(s.ctl, 'ssh.log')) ? readFileSync(join(s.ctl, 'ssh.log'), 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : []);

function payload(s) {
  const dir = join(s.root, 'payload');
  mkdirSync(dir);
  execFileSync('tar', ['xzf', join(s.ctl, 'payload.tgz'), '-C', dir]);
  return dir;
}

// A real ssh here reaches the family's router, so every test first proves the collector's shell finds the stub.
test('the scripts shell resolves ssh to the stub', (t) => {
  const s = scratch(t);
  const r = spawnSync('bash', ['-c', 'command -v ssh'], { env: s.env, encoding: 'utf8' });
  assert.equal(r.stdout.trim(), join(s.stubBin, 'ssh'));
});

test('install and restore refuse without a backup and never reach the router', (t) => {
  const s = scratch(t, { backup: false });
  for (const verb of ['install', 'restore']) {
    const r = run(s, verb);
    assert.notEqual(r.status, 0, verb);
    assert.match(r.stderr, /no router backup/);
  }
  assert.deepEqual(sshCalls(s), []);
});

test('install sends the files, the oldest backup and only ranked gambling names, then follows the log to installed', (t) => {
  const s = scratch(t);
  const later = join(s.state, 'router-backup-2026-11-01');
  mkdirSync(later);
  writeFileSync(join(later, 'sysupgrade-backup.tar.gz'), 'a later backup');
  const ranked = lists(s.ctl);
  writeFileSync(join(s.ctl, 'run.log'), 'dns-shield: fetching dnsmasq-full\ndns-shield: installed flash_free_kb=7000 ram_available_kb=26000\n');
  const r = run(s, 'install');
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /dns-shield: installed flash_free_kb=7000/);
  const p = payload(s);
  assert.deepEqual(readdirSync(join(p, 'stage')).sort(), ['20-dns-shield.nft', 'blocks.conf', 'dns-shield.init', 'gambling.conf', 'kid.conf']);
  for (const f of ['kid.conf', 'blocks.conf', 'dns-shield.init', '20-dns-shield.nft']) assert.equal(readFileSync(join(p, 'stage', f), 'utf8'), readFileSync(join(files, f), 'utf8'), f);
  assert.deepEqual(readFileSync(join(p, 'backup.tar.gz')), readFileSync(s.tgz));
  for (const f of ['install.sh', 'restore.sh', 'fetch.sh']) assert.equal(readFileSync(join(p, f), 'utf8'), readFileSync(join(files, f), 'utf8'), f);
  const gambling = readFileSync(join(p, 'stage', 'gambling.conf'), 'utf8').trim().split('\n');
  assert.deepEqual(gambling, ranked.map((d) => `address=/${d}/`));
  const calls = sshCalls(s);
  assert.ok(calls.some((a) => /setsid sh install\.sh/.test(a[a.length - 1])), 'install.sh started detached');
  for (const a of calls) {
    assert.deepEqual(a.slice(0, 2), ['-J', 'nuc']);
    assert.ok(a.includes('BatchMode=yes'));
    assert.ok(a.includes(`UserKnownHostsFile=${join(s.state, 'router_known_hosts')}`));
    assert.equal(a[a.length - 2], 'root@192.168.0.1');
    assert.equal(a[a.indexOf('-i') + 1], join(s.home, '.ssh', 'router'));
  }
  assert.ok(/rm -rf \/tmp\/dns-shield-setup$/.test(calls[calls.length - 1].at(-1)), 'the setup dir with the backup is removed');
  assert.doesNotMatch(r.stdout + r.stderr, /secret-psk|unbound variable/);
});

test('a failed install exits non-zero and takes the backup off the router', (t) => {
  const s = scratch(t, { jump: '' });
  lists(s.ctl);
  writeFileSync(join(s.ctl, 'run.log.1'), 'dns-shield: FAILED fw4 check, restoring\n');
  writeFileSync(join(s.ctl, 'run.log'), 'dns-shield: FAILED fw4 check, restoring\ndns-shield: restored\n');
  const r = run(s, 'install');
  assert.notEqual(r.status, 0);
  assert.match(r.stdout, /FAILED fw4 check/);
  assert.match(r.stdout, /dns-shield: restored/);
  const calls = sshCalls(s);
  // The restore reads the backup, so it stays on the router until the log says restored.
  assert.equal(calls.filter((a) => /cat .*run\.log/.test(a.at(-1))).length, 2);
  assert.ok(!calls[0].includes('-J'));
  assert.match(calls[calls.length - 1].at(-1), /rm -f \/tmp\/dns-shield-setup\/backup\.tar\.gz/);
});

test('restore sends only restore.sh and the backup, and follows the log to restored', (t) => {
  const s = scratch(t);
  writeFileSync(join(s.ctl, 'run.log'), 'dns-shield: restored\n');
  const r = run(s, 'restore');
  assert.equal(r.status, 0, r.stderr);
  assert.doesNotMatch(r.stderr, /unbound variable/);
  assert.deepEqual(readdirSync(payload(s)).sort(), ['backup.tar.gz', 'restore.sh']);
  assert.ok(sshCalls(s).some((a) => /setsid sh restore\.sh/.test(a.at(-1))));
});

test('backup refuses once DNS Shield is on the router, and otherwise keeps the router archive', (t) => {
  const s = scratch(t, { backup: false });
  writeFileSync(join(s.ctl, 'installed'), '');
  assert.notEqual(run(s, 'backup').status, 0);
  rmSync(join(s.ctl, 'installed'));
  const r = run(s, 'backup');
  assert.equal(r.status, 0, r.stderr);
  const out = r.stdout.trim();
  assert.deepEqual(readFileSync(out), readFileSync(s.tgz));
  assert.equal(execFileSync('stat', ['-c', '%a', out], { encoding: 'utf8' }).trim(), '600');
});

// The remote scripts run under busybox ash on the router.
test('install.sh, restore.sh and fetch.sh are plain sh', () => {
  for (const f of ['install.sh', 'restore.sh', 'fetch.sh']) {
    const r = spawnSync('bash', ['--posix', '-n', join(files, f)], { encoding: 'utf8' });
    assert.equal(r.status, 0, `${f}: ${r.stderr}`);
  }
});

test('install.sh downloads before it removes dnsmasq, checks fw4 before it restarts it, and places the nft include after the Kid sets exist', () => {
  const s = readFileSync(join(files, 'install.sh'), 'utf8');
  const at = (re) => {
    const i = s.search(re);
    assert.ok(i >= 0, String(re));
    return i;
  };
  assert.ok(at(/opkg download/) < at(/opkg remove dnsmasq/));
  assert.ok(at(/uci commit firewall/) < at(/cp "\$S\/stage\/20-dns-shield\.nft"/));
  assert.ok(at(/cp "\$S\/stage\/20-dns-shield\.nft"/) < at(/fw4 check/));
  assert.ok(at(/fw4 check/) < at(/\/etc\/init\.d\/firewall restart/));
  assert.ok(at(/opkg list-installed \| grep -q '\^dnsmasq-full '/) < at(/https-dns-proxy stop/));
  assert.match(s, /fail\(\) \{[^}]*sh "\$S\/restore\.sh"/);
});

test('restore.sh brings back exactly dhcp, firewall and https-dns-proxy and removes what install added', () => {
  const s = readFileSync(join(files, 'restore.sh'), 'utf8');
  assert.match(s, /tar xzf "\$S\/backup\.tar\.gz" etc\/config\/dhcp etc\/config\/firewall etc\/config\/https-dns-proxy \|\|/);
  for (const p of ['/etc/nftables.d/20-dns-shield.nft', '/etc/init.d/dns-shield', '/etc/dns-shield']) assert.ok(s.includes(p), p);
  assert.match(s, /https-dns-proxy enable/);
});

test('the Kid resolver config passes dnsmasq --test', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dns-kid-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const conf = readFileSync(join(files, 'kid.conf'), 'utf8')
    .replaceAll('/etc/dns-shield/', dir + '/')
    .replaceAll('/tmp/dns-shield/', dir + '/')
    .replace(/^user=.*$/m, `user=${process.env.USER || 'root'}`);
  writeFileSync(join(dir, 'kid.conf'), conf);
  writeFileSync(join(dir, 'blocks.conf'), readFileSync(join(files, 'blocks.conf')));
  writeFileSync(join(dir, 'gambling.conf'), 'address=/bet0.example/\n');
  writeFileSync(join(dir, 'allow.conf'), 'server=/khanacademy.org/94.140.14.14\n');
  const r = spawnSync('dnsmasq', ['--test', '-C', join(dir, 'kid.conf')], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.match(conf, /^port=5353$/m);
  assert.match(conf, /^server=94\.140\.14\.15$/m);
});

test('the nft include loads into a fw4 table that declares the Kid sets', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dns-nft-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const include = readFileSync(join(files, '20-dns-shield.nft'), 'utf8');
  writeFileSync(join(dir, 'fw4.nft'), `table inet fw4 {\n\tset kid {\n\t\ttype ipv4_addr\n\t}\n\tset kid_mac {\n\t\ttype ether_addr\n\t}\n${include}\n}\n`);
  const r = spawnSync('unshare', ['-rn', 'nft', '-c', '-f', join(dir, 'fw4.nft')], { encoding: 'utf8' });
  if (r.status !== 0 && /unshare/.test(r.stderr)) return t.skip('no user namespaces here');
  assert.equal(r.status, 0, r.stderr);
  for (const re of [/ip saddr @kid ip daddr @kid_block reject/, /th dport 853 reject/, /ether saddr @kid_mac meta nfproto ipv6 reject/, /dnat ip to 192\.168\.0\.1:5353/]) assert.match(include, re);
});

// A fake opkg whose feed holds dnsmasq-full's real dependency tree from the router: libgmp10 and the conntrack module are two levels down.
const OPKG = `#!/bin/sh
db='dnsmasq-full:libc, libubus20250102, libnettle8, libnetfilter-conntrack3 (>= 1.0), nftables-json
libnettle8:libc, libgmp10
libgmp10:libc
libnetfilter-conntrack3:libc, libnfnetlink0, kmod-nf-conntrack-netlink, libmnl0
kmod-nf-conntrack-netlink:kernel
libnfnetlink0:libc'
installed=' libc libubus20250102 nftables-json libnfnetlink0 libmnl0 kernel '
case $1 in
  status) case $installed in *" $2 "*) echo 'Status: install ok installed' ;; esac ;;
  info) echo "$db" | sed -n "s/^$2:/Depends: /p" ;;
  download) echo "$2" >>downloads; : >"$2.ipk" ;;
esac
`;

test('fetch.sh downloads dnsmasq-full with every dependency not installed, however deep', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'dns-fetch-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  writeFileSync(join(dir, 'bin', 'opkg'), OPKG, { mode: 0o755 });
  const r = spawnSync('sh', [join(files, 'fetch.sh'), 'dnsmasq-full'], { cwd: dir, env: { PATH: `${join(dir, 'bin')}:/usr/bin:/bin` }, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.deepEqual(readFileSync(join(dir, 'downloads'), 'utf8').trim().split('\n').sort(), ['dnsmasq-full', 'kmod-nf-conntrack-netlink', 'libgmp10', 'libnetfilter-conntrack3', 'libnettle8']);
});
