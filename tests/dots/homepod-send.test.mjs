// dots-homepod against fakes first on PATH: pw-link lists the sink's links from a file, dig answers as the HomePod for each host with a file under dns/, and cliairplay prints the lines the real one printed on the mini (2026-10-23) and records its argv and commands.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const bin = new URL('../../bin/dots-homepod', import.meta.url).pathname;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const TXT = 'acl=0 deviceid=22:61:3D:B7:0B:F7 features=0x4A7FCA00,0x3C354BD0 flags=0x80404 model=AudioAccessory5,1 osvers=27.0';
const STREAM = 'homepod:playback_FL\n  |<- mpv:output_FL\nhomepod:playback_FR\n  |<- mpv:output_FR\n';

async function until(what, fn, ms = 8000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (fn()) return;
    await sleep(50);
  }
  assert.fail('timed out waiting for ' + what);
}

const FAKES = {
  'pw-link': 'cat "$FAKE/links" 2>/dev/null\n',
  'pw-record': 'exec sleep 1000\n',
  ip: 'cat "$FAKE/addrs" 2>/dev/null\n',
  // dig +short +time=1 +tries=1 @<host> -p 5353 <name> <type>
  dig: `host=\${4#@}; name=$7; type=$8
echo "$host $type" >>"$FAKE/dig.log"
[[ -f $FAKE/dns/$host ]] || exit 0
if [[ $type == PTR ]]; then cat "$FAKE/dns/$host.ptr" 2>/dev/null; head -1 "$FAKE/dns/$host"
elif [[ $name == "$(head -1 "$FAKE/dns/$host")" ]]; then tail -1 "$FAKE/dns/$host" | sed 's/[^ ]*/"&"/g'
else echo '"deviceid=AA:BB:CC:DD:EE:FF" "model=Macmini9,1"'; fi
`,
  cliairplay: `run=$FAKE/runs/$(date +%s%N); mkdir -p "$run"; printf '%s\\n' "$@" >"$run/argv"
while (($#)); do [[ $1 == --cmdpipe ]] && cmd=$2; shift; done
if [[ $(cat "$FAKE/mode") == fail ]]; then
  echo '[STATUS] error code=connect_failed http=0 detail="native AirPlay 2 connect failed"'
  echo '[ERROR] Cannot connect to AirPlay 2 device'
  exit 1
fi
echo '[STATUS] route protocol=airplay2 flow=native timing=ptp buffered=0'
echo '[STATUS] connected'
echo '[STATUS] clock_ready mode=ptp state=cold streak_ms=0 exchanges=0 ready_in_ms=0 ready_at_unix_ms=0'
exec 4<"$cmd"
started=0
while :; do
  if read -r -t 0.1 line <&4; then
    echo "$line" >>"$run/cmds"
    case $line in
    ACTION=START)
      started=1
      echo '[STATUS] started requested_unix_ms=0 at_unix_ms=1792774045151'
      if [[ $(cat "$FAKE/mode") == stalled ]]; then
        echo '[STATUS] clock_ready mode=ptp state=stalled streak_ms=0 exchanges=0 ready_in_ms=0 ready_at_unix_ms=0'
      elif [[ $(cat "$FAKE/mode") == recovers ]]; then
        echo '[STATUS] clock_ready mode=ptp state=stalled streak_ms=0 exchanges=0 ready_in_ms=0 ready_at_unix_ms=0'
        sleep 0.4
        echo '[STATUS] clock_ready mode=ptp state=probing streak_ms=0 exchanges=2 ready_in_ms=2300 ready_at_unix_ms=1792774047451'
        echo '[STATUS] clock_ready mode=ptp state=ready streak_ms=2300 exchanges=12 ready_in_ms=0 ready_at_unix_ms=1792774047451'
      else
        echo '[STATUS] clock_ready mode=ptp state=ready streak_ms=2300 exchanges=12 ready_in_ms=0 ready_at_unix_ms=1792774047451'
      fi ;;
    ACTION=DISCONNECT) exit 0 ;;
    esac
  elif ((started)); then
    echo '[STATUS] playing elapsed_ms=756'
  fi
done
`,
};

function setup({ mode = 'ok', links = '', addrs = '' } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'homepod-send-'));
  const fake = join(root, 'fake');
  const path = join(root, 'bin');
  for (const d of [fake, path, join(fake, 'dns'), join(fake, 'runs'), join(root, 'run'), join(root, 'state')]) mkdirSync(d, { recursive: true });
  for (const [name, body] of Object.entries(FAKES)) writeFileSync(join(path, name), `#!/bin/bash\n${body}`, { mode: 0o755 });
  const env = {
    PATH: `${path}:${process.env.PATH}`,
    HOME: root,
    FAKE: fake,
    XDG_RUNTIME_DIR: join(root, 'run'),
    XDG_STATE_HOME: join(root, 'state'),
    DOTS_HOMEPOD_TICK: '0.1',
    DOTS_HOMEPOD_NETS: '127.0.0',
  };
  const t = {
    root,
    fake,
    out: '',
    set: (file, text) => writeFileSync(join(fake, file), text),
    homepod: (host, ptr = 'Office._airplay._tcp.local.', txt = TXT) => writeFileSync(join(fake, 'dns', host), `${ptr}\n${txt}\n`),
    gone: (host) => rmSync(join(fake, 'dns', host), { force: true }),
    // Each cliairplay start, oldest first, as { at (ms), argv, cmds }.
    runs: () =>
      readdirSync(join(fake, 'runs'))
        .sort()
        .map((r) => {
          const read = (f) => (existsSync(join(fake, 'runs', r, f)) ? readFileSync(join(fake, 'runs', r, f), 'utf8') : '');
          return { at: Number(r) / 1e6, argv: read('argv').trimEnd().split('\n'), cmds: read('cmds') };
        }),
    host: () => (existsSync(join(root, 'state/dots-homepod/host')) ? readFileSync(join(root, 'state/dots-homepod/host'), 'utf8').trim() : null),
    digs: () => (existsSync(join(fake, 'dig.log')) ? readFileSync(join(fake, 'dig.log'), 'utf8') : ''),
    start(nets) {
      t.proc = spawn('bash', [bin], { env: nets ? { ...env, DOTS_HOMEPOD_NETS: nets[0] } : env, stdio: ['ignore', 'pipe', 'pipe'], detached: true });
      t.proc.stdout.on('data', (d) => (t.out += d));
      t.proc.stderr.on('data', (d) => (t.out += d));
    },
    stop() {
      try {
        process.kill(-t.proc.pid, 'SIGKILL');
      } catch {}
    },
  };
  t.set('mode', mode);
  t.set('links', links);
  t.set('addrs', addrs);
  return t;
}

// A listener on <host>:7000, for the sweep to find.
function airplayPort(host) {
  const server = createServer((c) => c.destroy());
  return new Promise((r) => server.listen(7000, host, () => r(server)));
}

test('nothing playing into the sink starts no session', async (t) => {
  const h = setup();
  h.homepod('192.168.68.50');
  h.start();
  t.after(h.stop);
  await sleep(1500);
  assert.deepEqual(h.runs(), []);
  assert.equal(h.digs(), '', 'nobody is asked while nothing plays');
});

test('a stream into the sink plays on the HomePod at its known address, and the session ends 10 ticks after the stream stops', async (t) => {
  const h = setup({ links: STREAM });
  h.homepod('192.168.68.50');
  h.start();
  t.after(h.stop);
  await until('a session starts', () => h.runs()[0]?.cmds.includes('ACTION=START'));
  const { argv } = h.runs()[0];
  assert.deepEqual(argv.slice(0, 8), ['--protocol', 'auto', '--port', '7000', '--volume', '75', '--name', 'Office']);
  assert.deepEqual(argv.slice(8, 10), ['--txt', TXT]);
  assert.equal(argv[10], '--cmdpipe');
  assert.equal(argv[12], '192.168.68.50');
  assert.equal(h.host(), '192.168.68.50');
  assert.match(h.out, /^dots-homepod: playing on Office at 192\.168\.68\.50$/m);
  h.set('links', 'homepod:playback_FL\nhomepod:playback_FR\n');
  const stopped = Date.now();
  await until('the session is disconnected', () => h.runs()[0].cmds.includes('ACTION=DISCONNECT'), 4000);
  assert.ok(Date.now() - stopped >= 900, 'it waits out 10 ticks of quiet first');
  await sleep(1500);
  assert.equal(h.runs().length, 1, 'no new session while nothing plays');
});

test('a HomePod at neither known address is found by a sweep of the office net, and asked there first next time', async (t) => {
  const port = await airplayPort('127.0.0.7');
  t.after(() => port.close());
  const h = setup({ links: STREAM, addrs: '1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever preferred_lft forever\n' });
  h.homepod('127.0.0.7');
  h.start();
  t.after(h.stop);
  await until('a session starts at the swept host', () => h.runs()[0]?.argv.at(-1) === '127.0.0.7', 12000);
  assert.equal(h.host(), '127.0.0.7');
  h.stop();
  rmSync(join(h.fake, 'dig.log'));
  h.start();
  await until('a second session', () => h.runs().length === 2);
  assert.match(h.digs(), /^127\.0\.0\.7 PTR\n/, 'the last address is asked before any other');
});

test('a machine anywhere in the office net sweeps all of it, not only its own /24', async (t) => {
  const port = await airplayPort('127.0.1.7');
  t.after(() => port.close());
  const h = setup({ links: STREAM, addrs: '1: lo    inet 127.0.0.1/8 scope host lo\n' });
  h.homepod('127.0.1.7');
  h.start(['127.0.0 127.0.1']);
  t.after(h.stop);
  await until('a session starts at the host in the other /24', () => h.runs()[0]?.argv.at(-1) === '127.0.1.7', 15000);
});

test('a machine with no address in the office net sweeps nothing', async (t) => {
  const port = await airplayPort('127.0.0.7');
  t.after(() => port.close());
  const h = setup({ links: STREAM, addrs: '2: wlan0    inet 10.0.0.5/24 brd 10.0.0.255 scope global wlan0\n' });
  h.homepod('127.0.0.7');
  h.start();
  t.after(h.stop);
  await until('the HomePod is reported missing', () => /the HomePod answers nowhere on the office LAN/.test(h.out));
  assert.doesNotMatch(h.digs(), /127\.0\.0\.7/);
  assert.deepEqual(h.runs(), []);
});

test('a refused connect logs cliairplay\'s error and tries again 10 ticks later', async (t) => {
  const h = setup({ mode: 'fail', links: STREAM });
  h.homepod('192.168.68.50');
  h.start();
  t.after(h.stop);
  await until('two tries', () => h.runs().length >= 2);
  const [first, second] = h.runs();
  assert.ok(second.at - first.at >= 900, `the second try waits 10 ticks, not ${second.at - first.at} ms`);
  assert.match(h.out, /^\[STATUS\] error code=connect_failed/m);
  h.set('mode', 'ok');
  await until('the next try plays', () => h.runs().at(-1).cmds.includes('ACTION=START'));
});

test('a HomePod that never answers the PTP clock ends the session, naming the ports', async (t) => {
  const h = setup({ mode: 'stalled', links: STREAM });
  h.homepod('192.168.68.50');
  h.start();
  t.after(h.stop);
  await until('the stall is logged', () => /does not answer the PTP clock; UDP 319 and 320 must reach this machine/.test(h.out));
  assert.ok(h.runs()[0].cmds.includes('ACTION=DISCONNECT'), 'the session is ended, not just killed');
  await until('a later try', () => h.runs().length >= 2);
});

test('a clock that stalls for a moment and then answers keeps the session', async (t) => {
  const h = setup({ mode: 'recovers', links: STREAM });
  h.homepod('192.168.68.50');
  h.start();
  t.after(h.stop);
  await until('a session starts', () => h.runs()[0]?.cmds.includes('ACTION=START'));
  await sleep(2000);
  assert.doesNotMatch(h.out, /does not answer the PTP clock/);
  assert.deepEqual(h.runs().map((r) => r.cmds), ['ACTION=START\n']);
});

test('a missing cliairplay says so in the journal', async (t) => {
  const h = setup({ links: STREAM });
  rmSync(join(h.root, 'bin/cliairplay'));
  h.homepod('192.168.68.50');
  h.start();
  t.after(h.stop);
  await until('the failure is logged', () => /cliairplay: command not found/.test(h.out));
});

test('a HomePod that is found nowhere is looked for again after 30 ticks, then after twice as long each time', async (t) => {
  const h = setup({ links: STREAM });
  h.start();
  t.after(h.stop);
  const tries = () => [...h.digs().matchAll(/^192\.168\.68\.50 PTR$/gm)].length;
  const at = [];
  await until('three looks', () => {
    if (tries() > at.length) at.push(Date.now());
    return at.length >= 3;
  }, 15000);
  assert.ok(at[1] - at[0] >= 2900, `second look after ${at[1] - at[0]} ms`);
  assert.ok(at[2] - at[1] >= 5900, `third look after ${at[2] - at[1]} ms`);
});

test('a HomePod answering beside another AirPlay service on the same host is still found', async (t) => {
  const h = setup({ links: STREAM });
  h.homepod('192.168.68.50');
  writeFileSync(join(h.fake, 'dns', '192.168.68.50.ptr'), 'Studio Mac._airplay._tcp.local.\n');
  h.start();
  t.after(h.stop);
  await until('a session starts', () => h.runs()[0]?.cmds.includes('ACTION=START'));
  assert.equal(h.runs()[0].argv[7], 'Office');
});

test('a HomePod that moves to a new address mid-session plays again there', async (t) => {
  const port = await airplayPort('127.0.0.7');
  t.after(() => port.close());
  const h = setup({ links: STREAM, addrs: '1: lo    inet 127.0.0.1/8 scope host lo\n' });
  h.homepod('192.168.68.50');
  h.start();
  t.after(h.stop);
  await until('a session at the old address', () => h.runs()[0]?.cmds.includes('ACTION=START'));
  h.gone('192.168.68.50');
  h.homepod('127.0.0.7');
  await until('a session at the new address', () => h.runs().at(-1).argv.at(-1) === '127.0.0.7', 15000);
  assert.match(h.out, /the HomePod no longer answers at 192\.168\.68\.50/);
  assert.equal(h.host(), '127.0.0.7');
});

test('a forged service name reaches neither cliairplay nor the journal with controls or bidi marks', async (t) => {
  const h = setup({ links: STREAM });
  h.homepod('192.168.68.50', 'Off\x1b[2Jice‮\nx._airplay._tcp.local.');
  h.start();
  t.after(h.stop);
  await until('a session starts', () => h.runs()[0]?.cmds.includes('ACTION=START'));
  const name = h.runs()[0].argv[7];
  assert.doesNotMatch(name, /[\x00-\x1f\x7f‪-‮⁦-⁩]/);
  assert.doesNotMatch(h.out, /[\x00-\x09\x0b-\x1f\x7f‪-‮⁦-⁩]/);
});
