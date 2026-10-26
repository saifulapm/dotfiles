// dots-vnc against a stub ssh that plays the remote the way the real one does: fish runs the command words, and the remote's systemctl, niri, ss and wayvncctl are stubs with state in files.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const bin = new URL('../../bin/dots-vnc', import.meta.url).pathname;

// Real ssh resolves only the hosts it knows, forwards none of the local environment, and runs the command words through the remote's login shell, which is fish.
const SSH = `#!${process.execPath}
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const ctl = process.env.STUB_CTL;
const args = process.argv.slice(2);
fs.appendFileSync(ctl + '/ssh.log', JSON.stringify(args) + '\\n');
let i = 0;
while (i < args.length && args[i].startsWith('-')) i += /^-[oiJplF]$/.test(args[i]) ? 2 : 1;
const host = args[i];
if (host !== fs.readFileSync(ctl + '/host', 'utf8')) {
  process.stderr.write('ssh: Could not resolve hostname ' + host + ': Name or service not known\\n');
  process.exit(255);
}
// A machine tailscale still lists as online after it went away drops the connect, so ssh fails only at its ConnectTimeout.
if (fs.existsSync(ctl + '/down')) {
  const o = args.find((a) => a.startsWith('ConnectTimeout='));
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, (o ? Number(o.split('=')[1]) : 30) * 1000);
  process.stderr.write('ssh: connect to host ' + host + ' port 22: Connection timed out\\n');
  process.exit(255);
}
const remote = ctl + '/remote';
const r = spawnSync('/usr/bin/fish', ['--no-config', '-c', args.slice(i + 1).join(' ')], {
  stdio: 'inherit',
  env: { PATH: remote + '/bin', HOME: remote, STUB_REMOTE: remote },
});
process.exit(r.status ?? 255);
`;

// The remote's user manager: start and stop mark a unit active or not, and show-environment holds NIRI_SOCKET only while niri runs.
const SYSTEMCTL = `#!/bin/bash
# The stub's own tools, which the remote side's PATH leaves out.
PATH=/usr/bin
s=$STUB_REMOTE
echo "$*" >>"$s/systemctl.log"
[ "$1" = --user ] || exit 1
shift
case $1 in
  show-environment)
    echo "HOME=$s"
    [ -e "$s/niri" ] && echo "NIRI_SOCKET=/run/user/1000/niri.wayland-1.1234.sock"
    echo "XDG_RUNTIME_DIR=/run/user/1000"
    ;;
  is-active)
    if [ -e "$s/active/$2" ]; then echo active; else echo inactive; exit 3; fi
    ;;
  start | restart) : >"$s/active/$2" ;;
  stop) rm -f "$s/active/$2" "$s/loopback" "$s/ss.count" ;;
  list-units)
    for f in "$s"/active/*; do
      [ -e "$f" ] || continue
      u=\${f##*/}
      for pat in "$@"; do
        [[ $pat != -* && $pat != list-units && $u == $pat ]] && echo "$u loaded active running wayvnc for $u"
      done
    done
    ;;
  *) exit 1 ;;
esac
`;

const NIRI = `#!/bin/bash
# The stub's own tools, which the remote side's PATH leaves out.
PATH=/usr/bin
echo "$*" >>"$STUB_REMOTE/niri.log"
if [ -z "\${NIRI_SOCKET:-}" ]; then
  echo "Error: NIRI_SOCKET is not set, are you running this within niri?" >&2
  exit 1
fi
case "$*" in
  "msg -j focused-output") cat "$STUB_REMOTE/focused.json" ;;
  "msg -j outputs") cat "$STUB_REMOTE/outputs.json" ;;
  *) exit 1 ;;
esac
`;

// As on the nuc: while a wayvnc unit is active, tailscale serve's tailnet listeners show at once (15 ms after start), and wayvnc's own on 127.0.0.1 only from the third read (40-90 ms). A src filter keeps only its address's lines.
const SS = `#!/bin/bash
# The stub's own tools, which the remote side's PATH leaves out.
PATH=/usr/bin
s=$STUB_REMOTE
echo "$*" >>"$s/ss.log"
up=
for f in "$s"/active/wayvnc@*; do [ -e "$f" ] && up=1; done
[ -n "$up" ] || exit 0
n=$(($(cat "$s/ss.count" 2>/dev/null || echo 0) + 1))
echo "$n" >"$s/ss.count"
[ "$n" -ge 3 ] && [ ! -e "$s/never-binds" ] && : >"$s/loopback"
{
  [ -e "$s/loopback" ] && echo "LISTEN 0      16                       127.0.0.1:5900 0.0.0.0:*"
  echo "LISTEN 0      4096                100.103.142.87:5900 0.0.0.0:*"
  echo "LISTEN 0      4096   [fd7a:115c:a1e0::6034:8e58]:5900    [::]:*"
} | if [[ "$*" == *"src 127.0.0.1"* ]]; then grep ' 127.0.0.1:'; else cat; fi
exit 0
`;

const WAYVNCCTL = `#!/bin/bash
# The stub's own tools, which the remote side's PATH leaves out.
PATH=/usr/bin
echo "$*" >>"$STUB_REMOTE/wayvncctl.log"
cat "$STUB_REMOTE/clients.json"
`;

// Through tailscale serve, a viewer reaches wayvnc only once it listens on 127.0.0.1; before that tailscaled's dial is refused and wlvncc gives up, as it did live on 2026-10-27.
const WLVNCC = `#!${process.execPath}
const fs = require('node:fs');
const ctl = process.env.STUB_CTL;
if (!fs.existsSync(ctl + '/remote/loopback')) {
  fs.appendFileSync(ctl + '/refused.log', JSON.stringify(process.argv.slice(2)) + '\\n');
  process.stderr.write('Failed to connect to server\\n');
  process.exit(1);
}
fs.appendFileSync(ctl + '/wlvncc.log', JSON.stringify(process.argv.slice(2)) + '\\n');
process.exit(Number(fs.readFileSync(ctl + '/wlvncc-status', 'utf8')));
`;

// tailscale status --json as this tailnet answers it, cut to the fields read; a peer's Online goes false once tailscaled hears it left.
const STATUS = (online) => ({
  BackendState: 'Running',
  Self: { HostName: 'macbook-m2', DNSName: 'macbook.taila27604.ts.net.', Online: true },
  Peer: {
    'nodekey:181f': { HostName: 'fedora', DNSName: 'fedora.taila27604.ts.net.', Online: false, OS: 'linux' },
    'nodekey:47c9': { HostName: 'mac-mini-m2', DNSName: 'mini.taila27604.ts.net.', Online: online.mini, OS: 'linux' },
    'nodekey:8455': { HostName: 'Saifuls-Mac-mini', DNSName: 'saifuls-mac-mini.taila27604.ts.net.', Online: false, OS: 'macOS' },
    'nodekey:f78e': { HostName: 'nuc', DNSName: 'nuc.taila27604.ts.net.', Online: online.nuc, OS: 'linux' },
  },
});

// With tailscaled stopped, the CLI says so on stderr and exits 1.
const TAILSCALE = `#!/bin/bash
echo "$*" >>"$STUB_CTL/tailscale.log"
[ "$*" = "status --json" ] || exit 1
if [ ! -e "$STUB_CTL/status.json" ]; then
  echo 'failed to connect to local tailscaled; it doesn'"'"'t appear to be running (sudo systemctl start tailscaled ?)' >&2
  exit 1
fi
cat "$STUB_CTL/status.json"
`;

const NOTIFY = `#!/bin/bash
printf '%s\\0' "$@" >>"$STUB_CTL/notify.log"
echo >>"$STUB_CTL/notify.log"
`;

// Every log of every run, for the open-h264 check at the end.
const seen = [];

function exe(path, body) {
  writeFileSync(path, body);
  chmodSync(path, 0o755);
}

// outputs: the remote's outputs in niri's order; focused: the one with focus; active: units already running; online: what tailscale status says of each peer, or null when tailscaled is not running; proxy: the remote has built wl-uinput-proxy; binds: its wayvnc ever listens on 127.0.0.1.
function run(args, { host = 'nuc', down = false, niri = true, outputs = ['DP-3'], focused = 'DP-3', active = [], clients = [], wlvnccStatus = 0, online = { mini: true, nuc: true }, proxy = true, binds = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'dots-vnc-'));
  const ctl = join(dir, 'ctl');
  const stubs = join(dir, 'stubs');
  const remote = join(ctl, 'remote');
  mkdirSync(stubs, { recursive: true });
  mkdirSync(join(remote, 'bin'), { recursive: true });
  mkdirSync(join(remote, 'active'));
  writeFileSync(join(ctl, 'host'), host);
  if (down) writeFileSync(join(ctl, 'down'), '');
  writeFileSync(join(ctl, 'wlvncc-status'), String(wlvnccStatus));
  exe(join(stubs, 'ssh'), SSH);
  exe(join(stubs, 'wlvncc'), WLVNCC);
  exe(join(stubs, 'tailscale'), TAILSCALE);
  exe(join(stubs, 'notify-send'), NOTIFY);
  if (online) writeFileSync(join(ctl, 'status.json'), JSON.stringify(STATUS(online)));
  if (proxy) {
    mkdirSync(join(remote, '.local', 'bin'), { recursive: true });
    exe(join(remote, '.local', 'bin', 'wl-uinput-proxy'), '#!/bin/sh\n');
  }
  if (!binds) writeFileSync(join(remote, 'never-binds'), '');
  if (niri) writeFileSync(join(remote, 'niri'), '');
  writeFileSync(join(remote, 'outputs.json'), JSON.stringify(Object.fromEntries(outputs.map((name) => [name, { name, make: 'Dell', model: 'U2723QE' }]))));
  writeFileSync(join(remote, 'focused.json'), JSON.stringify({ name: focused, make: 'Dell', model: 'U2723QE' }));
  writeFileSync(join(remote, 'clients.json'), JSON.stringify(clients) + '\n');
  for (const u of active) writeFileSync(join(remote, 'active', u), '');
  if (active.length && binds) writeFileSync(join(remote, 'loopback'), '');
  exe(join(remote, 'bin', 'systemctl'), SYSTEMCTL);
  exe(join(remote, 'bin', 'niri'), NIRI);
  exe(join(remote, 'bin', 'ss'), SS);
  exe(join(remote, 'bin', 'wayvncctl'), WAYVNCCTL);
  for (const t of ['jq', 'bash', 'sleep']) symlinkSync('/usr/bin/' + t, join(remote, 'bin', t));
  const t0 = Date.now();
  const r = spawnSync(bin, args, {
    encoding: 'utf8',
    timeout: 20000,
    env: { PATH: `${stubs}:/usr/bin`, HOME: dir, STUB_CTL: ctl },
  });
  const read = (f) => (existsSync(f) ? readFileSync(f, 'utf8') : '');
  const lines = (f) => read(f).split('\n').filter(Boolean);
  const out = {
    ms: Date.now() - t0,
    status: r.status,
    notes: read(join(ctl, 'notify.log')).split('\n').filter(Boolean).map((l) => l.split('\0').slice(0, -1)),
    tailscale: lines(join(ctl, 'tailscale.log')),
    stderr: r.stderr,
    ssh: lines(join(ctl, 'ssh.log')).map((l) => JSON.parse(l)),
    wlvncc: lines(join(ctl, 'wlvncc.log')).map((l) => JSON.parse(l)),
    systemctl: lines(join(remote, 'systemctl.log')),
    wayvncctl: lines(join(remote, 'wayvncctl.log')),
  };
  for (const f of ['ssh.log', 'wlvncc.log', 'refused.log', 'remote/systemctl.log', 'remote/niri.log', 'remote/ss.log', 'remote/wayvncctl.log']) seen.push(read(join(ctl, f)));
  rmSync(dir, { recursive: true, force: true });
  return out;
}

const starts = (r) => r.systemctl.filter((l) => /^--user start /.test(l));
const restarts = (r) => r.systemctl.filter((l) => /^--user (re|try-re|reload-or-re)start /.test(l));
const stops = (r) => r.systemctl.filter((l) => /^--user stop /.test(l));

test('dots-vnc nuc starts the focused output unit once and opens wlvncc on nuc 5900 with ZRLE', () => {
  const r = run(['nuc'], { focused: 'DP-3' });
  assert.equal(r.stderr, '');
  assert.equal(r.status, 0);
  assert.deepEqual(starts(r), ['--user start wayvnc@DP-3.service']);
  assert.deepEqual(r.wlvncc, [['-e', 'zrle', '-i', '-n', '-a', 'dots-vnc', 'nuc', '5900']]);
});

test('on a remote with two outputs the unit started is the focused one, not the first', () => {
  const r = run(['nuc'], { outputs: ['DP-3', 'HDMI-A-1'], focused: 'HDMI-A-1' });
  assert.equal(r.status, 0);
  assert.deepEqual(starts(r), ['--user start wayvnc@HDMI-A-1.service']);
});

test('dots-vnc --tight nuc asks wlvncc for Tight', () => {
  const r = run(['--tight', 'nuc']);
  assert.equal(r.status, 0);
  assert.deepEqual(r.wlvncc, [['-e', 'tight', '-i', '-n', '-a', 'dots-vnc', 'nuc', '5900']]);
});

test('an already active unit is reused: no start, no restart, and wlvncc still runs', () => {
  const r = run(['nuc'], { active: ['wayvnc@DP-3.service'] });
  assert.equal(r.status, 0);
  assert.deepEqual(starts(r), []);
  assert.deepEqual(restarts(r), []);
  assert.deepEqual(r.wlvncc, [['-e', 'zrle', '-i', '-n', '-a', 'dots-vnc', 'nuc', '5900']]);
});

test('after wlvncc exits, an empty client list stops the started unit once, even when wlvncc failed', () => {
  const r = run(['nuc'], { focused: 'HDMI-A-1', clients: [], wlvnccStatus: 1 });
  assert.equal(r.wlvncc.length, 1);
  assert.deepEqual(stops(r), ['--user stop wayvnc@HDMI-A-1.service']);
});

test('after wlvncc exits, a client still listed leaves the unit running', () => {
  const r = run(['nuc'], { clients: [{ id: 2, address: '100.101.3.4', username: null, seat: 'seat0' }] });
  assert.equal(r.wlvncc.length, 1);
  assert.ok(r.wayvncctl.length > 0, 'the client list was read');
  assert.deepEqual(stops(r), []);
});

// The body of each notification raised, from notify-send's argv: [-a, dots-vnc, --, summary, body].
const bodies = (r) => r.notes.map((n) => n[n.length - 1]);

test('a machine tailscale lists offline is off at once: one notification, no ssh and no wlvncc', () => {
  const r = run(['nuc'], { online: { mini: true, nuc: false } });
  assert.deepEqual(bodies(r), ['nuc is off']);
  assert.deepEqual(r.notes[0].slice(0, 3), ['-a', 'dots-vnc', '--']);
  assert.ok(r.ms < 3000, `took ${r.ms} ms`);
  assert.notEqual(r.status, 0);
  assert.deepEqual(r.ssh, []);
  assert.deepEqual(r.wlvncc, []);
});

test('a machine tailscale still lists online but ssh cannot reach is unreachable within 10 s, and wlvncc never runs', () => {
  const r = run(['nuc'], { down: true });
  assert.deepEqual(bodies(r), ['nuc is unreachable']);
  assert.match(r.stderr, /^dots-vnc: nuc is unreachable$/m);
  assert.ok(r.ms < 10000, `took ${r.ms} ms`);
  assert.notEqual(r.status, 0);
  assert.equal(r.ssh.length, 1);
  assert.deepEqual(r.wlvncc, []);
});

test('with tailscaled not answering, the check falls to ssh: a reachable remote still opens', () => {
  const r = run(['nuc'], { online: null });
  assert.deepEqual(r.tailscale, ['status --json']);
  assert.deepEqual(bodies(r), []);
  assert.equal(r.status, 0);
  assert.equal(r.wlvncc.length, 1);
});

test('a remote with no niri session is named in a notification and no unit starts', () => {
  const r = run(['mini'], { host: 'mini', niri: false });
  assert.deepEqual(bodies(r), ['mini has no niri session']);
  assert.ok(r.ms < 10000, `took ${r.ms} ms`);
  assert.notEqual(r.status, 0);
  assert.deepEqual(starts(r), []);
  assert.deepEqual(r.wlvncc, []);
});

test('a remote that has not built wl-uinput-proxy yet says so and starts no unit', () => {
  const r = run(['nuc'], { proxy: false });
  assert.deepEqual(bodies(r), ['nuc has no wl-uinput-proxy yet: run dots update there']);
  assert.deepEqual(starts(r), []);
  assert.deepEqual(r.wlvncc, []);
});

test('a wayvnc that never listens is stopped before giving up, so the tailnet port closes', () => {
  const r = run(['nuc'], { binds: false });
  assert.deepEqual(bodies(r), ['wayvnc on nuc did not listen on 5900 within 8 s']);
  assert.deepEqual(starts(r), ['--user start wayvnc@DP-3.service']);
  assert.deepEqual(stops(r), ['--user stop wayvnc@DP-3.service']);
  assert.deepEqual(r.wlvncc, []);
});

test('a reused unit that does not listen is left to the viewer that started it', () => {
  const r = run(['nuc'], { active: ['wayvnc@DP-3.service'], binds: false });
  assert.deepEqual(stops(r), []);
});

test('an unknown name prints a usage line naming the three machines and exits 2 without ssh', () => {
  const r = run(['router']);
  assert.match(r.stderr, /^usage: dots-vnc .*\bmini\b.*\bnuc\b.*\bmacbook\b/);
  assert.equal(r.status, 2);
  assert.deepEqual(r.ssh, []);
  assert.deepEqual(r.wlvncc, []);
});

test('no call in any run names open-h264', () => {
  const all = seen.join('');
  assert.ok(all.includes('"zrle"') && all.includes('"tight"') && all.includes('start wayvnc@'), 'the runs above logged their calls');
  assert.equal(seen.filter((l) => l.includes('open-h264')).length, 0);
});
