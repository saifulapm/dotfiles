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
if (host !== fs.readFileSync(ctl + '/host', 'utf8') || fs.existsSync(ctl + '/down')) {
  process.stderr.write('ssh: Could not resolve hostname ' + host + ': Name or service not known\\n');
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
  stop) rm -f "$s/active/$2" ;;
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

// A 5900 listener shows only while some wayvnc unit is active.
const SS = `#!/bin/bash
# The stub's own tools, which the remote side's PATH leaves out.
PATH=/usr/bin
echo "$*" >>"$STUB_REMOTE/ss.log"
for f in "$STUB_REMOTE"/active/wayvnc@*; do
  [ -e "$f" ] && echo "LISTEN 0      16         127.0.0.1:5900      0.0.0.0:*" && break
done
exit 0
`;

const WAYVNCCTL = `#!/bin/bash
# The stub's own tools, which the remote side's PATH leaves out.
PATH=/usr/bin
echo "$*" >>"$STUB_REMOTE/wayvncctl.log"
cat "$STUB_REMOTE/clients.json"
`;

const WLVNCC = `#!${process.execPath}
const fs = require('node:fs');
fs.appendFileSync(process.env.STUB_CTL + '/wlvncc.log', JSON.stringify(process.argv.slice(2)) + '\\n');
process.exit(Number(fs.readFileSync(process.env.STUB_CTL + '/wlvncc-status', 'utf8')));
`;

// Every log of every run, for the open-h264 check at the end.
const seen = [];

function exe(path, body) {
  writeFileSync(path, body);
  chmodSync(path, 0o755);
}

// outputs: the remote's outputs in niri's order; focused: the one with focus; active: units already running.
function run(args, { host = 'nuc', down = false, niri = true, outputs = ['DP-3'], focused = 'DP-3', active = [], clients = [], wlvnccStatus = 0 } = {}) {
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
  if (niri) writeFileSync(join(remote, 'niri'), '');
  writeFileSync(join(remote, 'outputs.json'), JSON.stringify(Object.fromEntries(outputs.map((name) => [name, { name, make: 'Dell', model: 'U2723QE' }]))));
  writeFileSync(join(remote, 'focused.json'), JSON.stringify({ name: focused, make: 'Dell', model: 'U2723QE' }));
  writeFileSync(join(remote, 'clients.json'), JSON.stringify(clients) + '\n');
  for (const u of active) writeFileSync(join(remote, 'active', u), '');
  exe(join(remote, 'bin', 'systemctl'), SYSTEMCTL);
  exe(join(remote, 'bin', 'niri'), NIRI);
  exe(join(remote, 'bin', 'ss'), SS);
  exe(join(remote, 'bin', 'wayvncctl'), WAYVNCCTL);
  for (const t of ['jq', 'bash', 'sleep']) symlinkSync('/usr/bin/' + t, join(remote, 'bin', t));
  const r = spawnSync(bin, args, {
    encoding: 'utf8',
    timeout: 20000,
    env: { PATH: `${stubs}:/usr/bin`, HOME: dir, STUB_CTL: ctl },
  });
  const read = (f) => (existsSync(f) ? readFileSync(f, 'utf8') : '');
  const lines = (f) => read(f).split('\n').filter(Boolean);
  const out = {
    status: r.status,
    stderr: r.stderr,
    ssh: lines(join(ctl, 'ssh.log')).map((l) => JSON.parse(l)),
    wlvncc: lines(join(ctl, 'wlvncc.log')).map((l) => JSON.parse(l)),
    systemctl: lines(join(remote, 'systemctl.log')),
    wayvncctl: lines(join(remote, 'wayvncctl.log')),
  };
  for (const f of ['ssh.log', 'wlvncc.log', 'remote/systemctl.log', 'remote/niri.log', 'remote/ss.log', 'remote/wayvncctl.log']) seen.push(read(join(ctl, f)));
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

test('an unreachable host is named and wlvncc never runs', () => {
  const r = run(['nuc'], { down: true });
  assert.match(r.stderr, /^dots-vnc: nuc is unreachable$/m);
  assert.notEqual(r.status, 0);
  assert.equal(r.ssh.length, 1);
  assert.deepEqual(r.wlvncc, []);
});

test('a remote with no niri session is named and wlvncc never runs', () => {
  const r = run(['nuc'], { niri: false });
  assert.match(r.stderr, /^dots-vnc: nuc has no niri session$/m);
  assert.notEqual(r.status, 0);
  assert.deepEqual(starts(r), []);
  assert.deepEqual(r.wlvncc, []);
});

test('an unknown name prints usage and exits 2 without ssh', () => {
  const r = run(['router']);
  assert.match(r.stderr, /^usage: dots-vnc /);
  assert.equal(r.status, 2);
  assert.deepEqual(r.ssh, []);
  assert.deepEqual(r.wlvncc, []);
});

test('no call in any run names open-h264', () => {
  const all = seen.join('');
  assert.ok(all.includes('"zrle"') && all.includes('"tight"') && all.includes('start wayvnc@'), 'the runs above logged their calls');
  assert.equal(seen.filter((l) => l.includes('open-h264')).length, 0);
});
