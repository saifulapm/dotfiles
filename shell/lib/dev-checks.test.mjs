import { test } from 'node:test';
import assert from 'node:assert/strict';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// A redirect on a check line silences the check's own ok or FAIL line, so the run hides the result.
const dir = new URL('../../tests/dev/', import.meta.url).pathname;

test('no check line in tests/dev redirects its output', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    readFileSync(dir + f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/^\s*check\s/.test(line) && /(>|>>)\s*\/dev\/null\s*$/.test(line) && !/'[^']*>\s*\/dev\/null\s*'\s*$/.test(line)) found.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(found, []);
});

// Two nested sessions at once stretch every timing, so each check waits its turn for one shared lock.
test('lib.sh takes the nested-check lock before it starts dots-dev, and dots-dev does not inherit it', () => {
  const lib = readFileSync(new URL('../../tests/dev/lib.sh', import.meta.url), 'utf8');
  const lock = lib.search(/flock\s+-w\s+\d+\s+9\b/);
  const start = lib.search(/"\$repo\/bin\/dots-dev"[^\n]*9>&-/);
  assert.ok(lock >= 0, 'lib.sh runs flock -w <s> 9');
  assert.ok(start > lock, 'dots-dev starts after the lock, with fd 9 closed');
});

// A locked live session and monitors an agent unlock turned off both slow the nested output; the FAIL names which, from the live shell's lock state.
test('lib.sh\'s slow-drawing FAIL prints the live session\'s lock state', () => {
  const lib = readFileSync(new URL('../../tests/dev/lib.sh', import.meta.url), 'utf8');
  const block = lib.slice(lib.indexOf('draws about once a second: '), lib.indexOf('exit 2', lib.indexOf('draws about once a second: ')));
  assert.match(block, /WAYLAND_DISPLAY="\$live_wl"[^\n]*bin\/dots-call" lock state/, 'the FAIL reads the live shell\'s lock state');
  assert.match(block, /locked[^\n]*heldBy[^\n]*monitorsOff/, 'and prints locked, heldBy and monitorsOff');
  assert.ok(lib.indexOf('live_wl=') < lib.indexOf('source "$dev_out"'), 'live_wl is taken before the nested env replaces WAYLAND_DISPLAY');
});

// An agent unlock's darken left the live output off under a lease (m88), and the nested output drew once a second, so lib.sh lights it before it times a frame.
test('lib.sh powers on the live output through the live niri before its draw-rate guard', () => {
  const lib = readFileSync(new URL('../../tests/dev/lib.sh', import.meta.url), 'utf8');
  const on = lib.search(/NIRI_SOCKET="\$live_niri" niri msg action power-on-monitors/);
  assert.ok(on >= 0, 'lib.sh runs niri msg action power-on-monitors on the live socket');
  assert.ok(on < lib.indexOf('grim_ms >/dev/null'), 'before the first frame is timed');
  assert.ok(lib.indexOf('live_niri=') < lib.indexOf('source "$dev_out"'), 'live_niri is taken before the nested env replaces NIRI_SOCKET');
});

// A walker's orphaned sleep held the lock past its walk twice (m56, m75); the FAIL names who holds it, so nothing is killed blind.
test('lib-lock-holders.sh names each process holding the lock file, and lib.sh\'s lock FAIL runs it', () => {
  const scratch = mkdtempSync(join(tmpdir(), 'lock-holders-'));
  const lock = join(scratch, 'dots-dev-check.lock');
  writeFileSync(lock, '');
  const holder = spawn('bash', ['-c', `exec 9>"${lock}"; exec sleep 30`], { stdio: 'ignore' });
  try {
    let out = '';
    for (let i = 0; i < 50 && !out.includes('sleep'); i++) {
      out = spawnSync('bash', [dir + 'lib-lock-holders.sh', lock], { encoding: 'utf8' }).stdout;
      if (!out.includes('sleep')) spawnSync('sleep', ['0.05']);
    }
    assert.match(out, new RegExp(`\\b${holder.pid}\\b.*sleep 30`), 'prints the holder\'s pid and command line');
  } finally {
    holder.kill();
    rmSync(scratch, { recursive: true, force: true });
  }
  const lib = readFileSync(new URL('../../tests/dev/lib.sh', import.meta.url), 'utf8');
  const fail = lib.slice(lib.search(/flock\s+-w\s+\d+\s+9\b/)).split('\n')[0];
  assert.match(fail, /lib-lock-holders\.sh/, 'the 15 min FAIL prints the holders');
});

// bin/ is on the live desktop's PATH, so a fake ddcutil there would hide the real one from the live shell.
test('the fake ddcutil lives in dev/path, never in bin/', () => {
  assert.ok(existsSync(new URL('../../dev/path/ddcutil', import.meta.url)));
  assert.ok(!existsSync(new URL('../../bin/ddcutil', import.meta.url)));
});

// The live foot.ini themes every foot and its [colors-light] beats -o colors.*, so a nested foot reads /dev/null (themes.sh reads it on purpose).
test('every foot a tests/dev script spawns passes -c /dev/null', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh') && f !== 'themes.sh')) {
    readFileSync(dir + f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/spawn\s+--\s+foot\b/.test(line) && !/\bfoot\s+-c\s+\/dev\/null\b/.test(line)) found.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(found, [], 'foot spawned without -c /dev/null');
});

// The shell centres a card at Math.round((width - N) / 2), so an odd width rounds up: (ow - N + 1) / 2 in bash.
test('no tests/dev script floors a centred card x position', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    readFileSync(dir + f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/\(\(?\s*ow\s*-\s*\d+\s*\)\s*\/\s*2/.test(line) && !/ow\s*-\s*\d+\s*\+\s*1\s*\)\s*\/\s*2/.test(line)) found.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(found, [], 'card x floored, use (ow - N + 1) / 2');
});

// An agent shell without WAYLAND_DISPLAY gets niri's "error initializing the TTY backend" minutes into a run, so lib.sh stops first and names the fix.
test('lib.sh stops at once on an empty WAYLAND_DISPLAY, naming the fix, before it starts dots-dev', () => {
  const root = mkdtempSync(join(tmpdir(), 'dev-lib-'));
  try {
    mkdirSync(join(root, 'tests/dev'), { recursive: true });
    mkdirSync(join(root, 'bin'));
    copyFileSync(new URL('../../tests/dev/lib.sh', import.meta.url), join(root, 'tests/dev/lib.sh'));
    writeFileSync(join(root, 'bin/dots-dev'), `#!/bin/sh\ntouch ${root}/started\n`, { mode: 0o755 });
    const r = spawnSync('bash', ['-c', `source ${root}/tests/dev/lib.sh`], {
      env: { ...process.env, WAYLAND_DISPLAY: '', XDG_RUNTIME_DIR: root },
      encoding: 'utf8',
      timeout: 3000,
    });
    assert.notEqual(r.status, 0);
    assert.match(r.stdout, /WAYLAND_DISPLAY=wayland-1/);
    assert.ok(!existsSync(join(root, 'started')), 'dots-dev never ran');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// The shell unit gets the live user manager's env, so a DOTS_* that bin/dots-dev exports reaches the nested shell only through its -E.
test('every DOTS_* that dots-dev exports is passed to the shell unit by name', () => {
  const dev = readFileSync(new URL('../../bin/dots-dev', import.meta.url), 'utf8');
  const unit = readFileSync(new URL('../../bin/dots-dev-shell', import.meta.url), 'utf8');
  const exported = [...dev.matchAll(/^export\s+(.*)$/gm)].flatMap((m) => [...m[1].matchAll(/\b(DOTS_\w+)=/g)].map((v) => v[1]));
  const qs = unit.slice(0, unit.indexOf('qs --log-rules'));
  const passed = new Set([...qs.matchAll(/-E\s+(\w+)/g)].map((m) => m[1]));
  // DOTS_DEV_UNIT names the unit itself, and only dots-dev-shell and the bench read it.
  const missing = exported.filter((v) => v !== 'DOTS_DEV_UNIT' && !passed.has(v));
  assert.ok(exported.includes('DOTS_ACCOUNTS'), 'read the exports of bin/dots-dev');
  assert.deepEqual(missing, []);
});

// m100's walker sat 20 minutes on the nested session's own 300 s idle lock; only a check that asks for the idle steps gets them.
test('dots-dev starts the nested shell with idle locking off unless a check sets DOTS_DEV_IDLE=on, and only the idle checks do', () => {
  const dev = readFileSync(new URL('../../bin/dots-dev', import.meta.url), 'utf8');
  assert.match(dev, /^export DOTS_IDLE=\$\{DOTS_DEV_IDLE:-off\}$/m);
  const idle = readFileSync(new URL('../Idle.qml', import.meta.url), 'utf8');
  assert.match(idle, /property var times: Lib\.startTimes\(Quickshell\.env\("DOTS_IDLE"\)\)/);
  const dir = new URL('../../tests/dev/', import.meta.url);
  const asking = readdirSync(dir).filter((f) => f.endsWith('.sh') && /^export DOTS_DEV_IDLE=on$/m.test(readFileSync(new URL(f, dir), 'utf8')));
  assert.deepEqual(asking.sort(), ['idle.sh', 'presence.sh']);
});

// m100's bench died twice typing a scheme name when the idle live monitors went off mid-run; a power-on beside it every 20 s let it pass.
test('dots-bench powers the live monitors on every 20 s through the live niri while it runs, and stops that in its cleanup', () => {
  const bench = readFileSync(new URL('../../bin/dots-bench', import.meta.url), 'utf8');
  const loop = bench.match(/^\s*\(while :; do NIRI_SOCKET="\$live_niri" niri msg action power-on-monitors >\/dev\/null 2>&1; sleep (\d+); done\) 9>&- &$/m);
  assert.ok(loop, 'a background power-on loop through $live_niri, with the lock fd closed');
  assert.ok(Number(loop[1]) <= 20);
  assert.match(bench, /^\s*monitors_pid=\$!$/m);
  assert.match(bench, /^cleanup\(\) \{[^\n]*kill "\$monitors_pid"/m);
});

// A DevTools eval exits 0 whatever it answers, so `check ... page '<js>'` passed on false in m33; check refuses page, row and cdp as its command.
test('check refuses a DevTools eval as its command, bare or under until_ok', () => {
  const lib = readFileSync(new URL('../../tests/dev/lib.sh', import.meta.url), 'utf8');
  const fn = lib.match(/^check\(\) \{[\s\S]*?^\}/m);
  assert.ok(fn, 'lib.sh defines check()');
  const script = `${fn[0]}
fails=0
page() { echo false; }
row() { echo false; }
cdp() { echo false; }
yes_fn() { true; }
check "bare page" page 'x'
check "waited row" until_ok 100 row a b
check "cdp eval" cdp eval newtab.html 'x'
check "a function" yes_fn
echo "fails=$fails"`;
  const r = spawnSync('bash', ['-c', script], { encoding: 'utf8', timeout: 3000 });
  assert.match(r.stdout, /^FAIL bare page/m);
  assert.match(r.stdout, /^FAIL waited row/m);
  assert.match(r.stdout, /^FAIL cdp eval/m);
  assert.match(r.stdout, /^ok   a function$/m);
  assert.match(r.stdout, /^fails=3$/m);
});

// m80: an unbound $name killed picker-specimen.sh after 3 of 14 checks, and every summary counting ok and FAIL lines read it green.
test('a check that dies before any FAIL prints one from lib.sh\'s EXIT trap, and a check that failed or passed gets none', () => {
  const lib = readFileSync(new URL('../../tests/dev/lib.sh', import.meta.url), 'utf8');
  const fn = lib.match(/^dev_exit\(\) \{[\s\S]*?^\}/m);
  assert.ok(fn, 'lib.sh defines dev_exit()');
  const run = (body) =>
    spawnSync('bash', ['-c', `set -uo pipefail
${fn[0]}
qml_errors() { :; }
cleanup() { :; }
dev_stop() { :; }
dev_out=/nonexistent dev_log=/nonexistent
fails=0
trap dev_exit EXIT
${body}`], { encoding: 'utf8', timeout: 3000 });
  const died = run('echo "ok   one"\necho "$name"\necho "ok   two"');
  assert.notEqual(died.status, 0);
  assert.match(died.stdout, /^FAIL .*exit 1.* before any check failed/m);
  const failed = run('fails=1\necho "FAIL one"\nexit $((fails > 0))');
  assert.equal(failed.status, 1);
  assert.deepEqual(failed.stdout.match(/^FAIL/gm), ['FAIL']);
  const passed = run('echo "ok   one"\nexit $((fails > 0))');
  assert.equal(passed.status, 0);
  assert.doesNotMatch(passed.stdout, /^FAIL/m);
});

// m82 and m84: an edit in the tree a check ran its shell from hot-reloaded that shell mid-check, and the red that ran proved nothing.
test("lib.sh's EXIT trap fails a check when a file under its shell changed while it ran, and names the file", () => {
  const lib = readFileSync(new URL('../../tests/dev/lib.sh', import.meta.url), 'utf8');
  const fn = lib.match(/^dev_exit\(\) \{[\s\S]*?^\}/m);
  assert.ok(fn, 'lib.sh defines dev_exit()');
  assert.match(lib, /^shell_watch=\$\{DOTS_DEV_SHELL:-\$repo\/shell\}$/m, 'lib.sh watches the shell tree dots-dev loads');
  assert.ok(lib.search(/^started=\$\(mktemp\)$/m) >= 0 && lib.search(/^started=\$\(mktemp\)$/m) < lib.search(/"\$repo\/bin\/dots-dev"/), 'lib.sh marks the start before dots-dev runs');
  const root = mkdtempSync(join(tmpdir(), 'dev-exit-'));
  try {
    mkdirSync(join(root, 'shell/lib'), { recursive: true });
    writeFileSync(join(root, 'shell/lib/a.mjs'), '');
    const run = (body) =>
      spawnSync('bash', ['-c', `set -uo pipefail
${fn[0]}
qml_errors() { :; }
cleanup() { :; }
dev_stop() { :; }
dev_out=/nonexistent dev_log=/nonexistent
shell_watch=${root}/shell
fails=0
started=$(mktemp)
trap dev_exit EXIT
${body}`], { encoding: 'utf8', timeout: 3000 });
    const quiet = run('echo "ok   one"\nexit $((fails > 0))');
    assert.equal(quiet.status, 0);
    assert.doesNotMatch(quiet.stdout, /^FAIL/m);
    const edited = run(`sleep 0.02\ntouch ${root}/shell/lib/a.mjs\necho "ok   one"\nexit $((fails > 0))`);
    assert.equal(edited.status, 1);
    assert.match(edited.stdout, /^FAIL lib\/a\.mjs changed while the check ran/m);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// m104's live session idle-locked mid-batch and island-notifs-rules.sh lost keys on a 6 s hold, which read as the shell's fault; the trap says the session locked.
test("lib.sh's EXIT trap fails a check when the live session locked while it ran, and stays quiet when it did not", () => {
  const lib = readFileSync(new URL('../../tests/dev/lib.sh', import.meta.url), 'utf8');
  const fn = lib.match(/^dev_exit\(\) \{[\s\S]*?^\}/m);
  assert.ok(fn, 'lib.sh defines dev_exit()');
  const reader = lib.match(/^live_lock\(\) \{[^\n]*WAYLAND_DISPLAY="\$live_wl"[^\n]*bin\/dots-call" lock state[^\n]*\}$/m);
  assert.ok(reader, 'live_lock() reads the live shell\'s lock state');
  const start = lib.search(/^lock_start=\$\(live_lock\)$/m);
  assert.ok(start > lib.indexOf('draws about once a second: '), 'lib.sh records the lock state once the draw-rate guard passed');
  const run = (now) =>
    spawnSync('bash', ['-c', `set -uo pipefail
${fn[0]}
qml_errors() { :; }
cleanup() { :; }
dev_stop() { :; }
live_lock() { echo '${now}'; }
lock_start='{"locked":false,"heldBy":"","monitorsOff":0,"leaseUntil":0}'
dev_out=/nonexistent dev_log=/nonexistent shell_watch=/nonexistent started=/nonexistent
fails=0
trap dev_exit EXIT
echo "ok   one"
exit $((fails > 0))`], { encoding: 'utf8', timeout: 3000 });
  const locked = run('{"locked":true,"heldBy":"","monitorsOff":0,"leaseUntil":0}');
  assert.equal(locked.status, 1);
  assert.match(locked.stdout, /^FAIL the live session locked during this check \(\{"locked":true.*\): rerun from the first FAIL under a lease$/m);
  const unlocked = run('{"locked":false,"heldBy":"","monitorsOff":0,"leaseUntil":0}');
  assert.equal(unlocked.status, 0);
  assert.doesNotMatch(unlocked.stdout, /^FAIL/m);
});

// qs writes its log and QML warnings to stdout, so a check that kept only Files' stderr read an empty log and its "no QML errors" passed blind (m34).
test('every tests/dev script that starts Files keeps its stdout and stderr in one log', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    readFileSync(dir + f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/exec dots-files\b/.test(line) && !/exec dots-files\s*>>?\s*\S+\s+2>&1/.test(line)) found.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(found, []);
});

// bash runs `${1:+FAKE_CUT=$1} "$bin"` with FAKE_CUT=... as the command, not as an assignment, so an expanded assignment goes through env.
test('no line in tests/ or bin/ starts with an assignment that comes from an expansion', () => {
  const root = new URL('../../', import.meta.url).pathname;
  const files = readdirSync(root + 'tests', { recursive: true })
    .map((f) => 'tests/' + f)
    .concat(readdirSync(root + 'bin').map((f) => 'bin/' + f))
    .filter((f) => statSync(root + f).isFile());
  const found = [];
  for (const f of files) {
    readFileSync(root + f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/^\s*"?\$\{\w+:\+\w+=/.test(line)) found.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(found, [], 'start the line with env');
});

// lib.sh's EXIT trap reads the shell's QML errors, runs cleanup() and stops the nested niri; config-rejected.sh replaced it with its own and left seven sessions running (m47), so a check's teardown goes in cleanup().
test('no tests/dev script sets an EXIT trap after sourcing lib.sh', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh') && f !== 'lib.sh')) {
    const lines = readFileSync(dir + f, 'utf8').split('\n');
    const from = lines.findIndex((l) => /^\s*(source|\.)\s.*\blib\.sh\b/.test(l));
    if (from < 0) continue;
    lines.forEach((line, i) => {
      if (i > from && /^\s*trap\s.*\bEXIT\b/.test(line)) found.push(`${f}:${i + 1}`);
    });
  }
  assert.deepEqual(found, [], 'put the teardown in cleanup()');
});

// lib.sh runs dots-dev in the background, so a bare wait in a check waits for the nested session itself and hangs while holding the nested-check lock (m48); wait by pid.
test('no tests/dev script runs a bare wait', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    readFileSync(dir + f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/(^|[;&|(]|\bthen|\bdo)\s*wait\s*($|[;&|)#])/.test(line)) found.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(found, [], 'wait "$pid"');
});

// until_ok runs its command again on each try, but a "$(...)" in its arguments is read once, before the first, so the wait passes or times out on a stale value (m69); wrap the read in a function.
test('no tests/dev script waits on a value read once with until_ok test "$(...)"', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    readFileSync(dir + f, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/\buntil_ok\s+\d+\s+(test|\[)\s+[^;&|]*\$\(/.test(line)) found.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(found, [], 'until_ok <ms> <function that reads afresh>');
});

// The Apps read their theme from XDG_STATE_HOME/dots, so a launch line that moves it leaves the App drawing with no tokens unless the nested session's state is linked in (m71).
test('a tests/dev script that moves XDG_STATE_HOME links the nested session state/dots into it', () => {
  const found = readdirSync(dir)
    .filter((f) => f.endsWith('.sh'))
    .filter((f) => {
      const text = readFileSync(dir + f, 'utf8');
      return /(^|[\s"])XDG_STATE_HOME=/m.test(text) && !/\bln -s "\$DOTS_DEV_DIR\/state\/dots"/.test(text);
    });
  assert.deepEqual(found, [], 'drop XDG_STATE_HOME= from the launch line, or ln -s "$DOTS_DEV_DIR/state/dots" into its state dir');
});

// A fake a check writes and marks executable must start with #!, since the shell's Process cannot run a script without one and the check then fails on its fake (m101's island-ask fake mem).
export function fakesWithoutShebang(text) {
  const lines = text.split('\n');
  const marked = new Set();
  for (const line of lines) {
    const m = line.match(/^\s*chmod\s+\+x\s+(.*)$/);
    if (m) for (const t of m[1].match(/"[^"]*"|\S+/g)) marked.add(t.replace(/^"|"$/g, ''));
  }
  const found = [];
  lines.forEach((line, i) => {
    const heredoc = line.match(/^\s*cat\s+>\s*"?([^"\s]+)"?\s+<<-?\s*['"]?\w+/);
    const printf = line.match(/^\s*printf\s+(['"])(.*?)\1.*>\s*"?([^"\s]+)"?\s*$/);
    if (heredoc && marked.has(heredoc[1]) && !/^#!/.test(lines[i + 1] ?? '')) found.push(i + 1);
    if (printf && marked.has(printf[3]) && !/^#!/.test(printf[2])) found.push(i + 1);
  });
  return found;
}

// notify-send -A waits for an action, so one run in the foreground holds the check until it times out (m101's island-focus hung 9 minutes).
export function foregroundActionSends(text) {
  const found = [];
  text.split('\n').forEach((line, i) => {
    const code = line.replace(/(^|\s)#.*$/, '');
    if (/\bnotify-send\b/.test(code) && /\s-A\b/.test(code) && !/&\s*$/.test(code)) found.push(i + 1);
  });
  return found;
}

// island-control.sh's fake NetworkManager, started with &, kept the nested-check lock's fd 9 past the check, and every later check waited on the lock.
export function backgroundWithLock(text) {
  const found = [];
  text.split('\n').forEach((line, i) => {
    const code = line.replace(/(^|\s)#.*$/, '');
    // A start mid-line is followed by what a helper does next: echo $!, a pid kept in a name, or the function's close.
    if (/(^|[^&;|>])&(\s*$|\s+(echo\b|[A-Za-z_][A-Za-z_0-9]*\+?=|\}))/.test(code) && !/9>&-/.test(code)) found.push(i + 1);
  });
  return found;
}

test('the fake and notify-send lints catch the shapes that broke the island checks', () => {
  assert.deepEqual(fakesWithoutShebang('cat >"$fake/mem" <<EOF\nprintf hi\nEOF\nchmod +x "$fake/mem"\n'), [1]);
  assert.deepEqual(fakesWithoutShebang("printf 'echo hi\\n' >\"$f/claude\"\nchmod +x \"$f/claude\"\n"), [1]);
  assert.deepEqual(fakesWithoutShebang('cat >"$fake/mem" <<EOF\n#!/bin/sh\nEOF\nchmod +x "$fake/mem"\n'), []);
  assert.deepEqual(foregroundActionSends('notify-send -t 0 -A ok=OK "Deploy?" >/dev/null\n'), [1]);
  assert.deepEqual(foregroundActionSends('notify-send -t 0 -A ok=OK "Deploy?" >/dev/null &\n# notify-send -A waits\n'), []);
  assert.deepEqual(backgroundWithLock('"$fake/NetworkManager" >"$log" 2>&1 &\nfake_pid=$!\n'), [1]);
  assert.deepEqual(backgroundWithLock('sleep 30 & # held\n'), [1]);
  assert.deepEqual(backgroundWithLock('"$fake/NetworkManager" >"$log" 2>&1 9>&- &\nsleep 30 9>&- & # held\n'), []);
  assert.deepEqual(backgroundWithLock('a && b &&\n  c\ncase $x in a) b ;& c) d ;;& esac\n'), []);
  // A background start in the middle of a line, as a helper writes one, counts too.
  assert.deepEqual(backgroundWithLock('ask() { notify-send "$@" >"$out" & sender=$!; }\nrun() { sleep 9 2>&1 & }\n'), [1, 2]);
  assert.deepEqual(backgroundWithLock('ask() { notify-send "$@" >"$out" 9>&- & sender=$!; }\nx 2>&1 | y\n'), []);
});

test('every background process a tests/dev script starts closes the nested-check lock fd 9', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    for (const n of backgroundWithLock(readFileSync(dir + f, 'utf8'))) found.push(`${f}:${n}`);
  }
  assert.deepEqual(found, [], 'add 9>&- to the command before its &');
});

test('every fake a tests/dev script marks executable starts with #!, and every notify-send -A runs in the background', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    const text = readFileSync(dir + f, 'utf8');
    for (const n of fakesWithoutShebang(text)) found.push(`${f}:${n} fake without #!`);
    for (const n of foregroundActionSends(text)) found.push(`${f}:${n} notify-send -A in the foreground`);
  }
  assert.deepEqual(found, []);
});

// m102 to m105 moved surfaces into the island and dozens of checks stalled on state keys the new state() dropped (settled, cardBox, legend, tabFill); these files' state() literals, each after its Ipc target where one is named, make a surface's keys.
const stateSources = {
  island: [['Desk.qml', 'target: "island"']],
  launcher: [['shell.qml', 'target: "launcher"'], ['Launcher.qml']],
  cheatsheet: [['shell.qml', 'target: "cheatsheet"'], ['CheatSheet.qml']],
  control: [['shell.qml', 'target: "control"'], ['Control.qml'], ['ControlWifi.qml'], ['ControlAudio.qml'], ['ControlBluetooth.qml'], ['ControlPower.qml'], ['ControlDisplay.qml'], ['ControlRoute.qml']],
  notifs: [['shell.qml', 'target: "notifs"'], ['Notifications.qml']],
  record: [['shell.qml', 'target: "record"'], ['Recorder.qml']],
  pass: [['shell.qml', 'target: "pass"'], ['Pass.qml']],
  tailscale: [['shell.qml', 'target: "tailscale"'], ['Tailscale.qml']],
  accounts: [['shell.qml', 'target: "accounts"'], ['Accounts.qml']],
  dns: [['shell.qml', 'target: "dns"'], ['Dns.qml']],
  goals: [['shell.qml', 'target: "goals"'], ['Goals.qml']],
  // Each takeover's Ipc target merges the prompt's state() with what its agent adds (registered, active, waiting).
  polkit: [['Polkit.qml', 'target: "polkit"'], ['PolkitPrompt.qml']],
  pinentry: [['Pinentry.qml', 'target: "pinentry"'], ['PinentryPrompt.qml']],
  picker: [['Portal.qml', 'target: "picker"'], ['FilePicker.qml']],
  pairing: [['Pairing.qml', 'target: "pairing"'], ['PairingPrompt.qml']],
};

// Blanks comments and string contents, so a brace or an apostrophe in either cannot shift the scan.
function jsCode(text) {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '/' && text[i + 1] === '/') {
      while (i < text.length && text[i] !== '\n') i++;
      out += '\n';
    } else if (c === '/' && text[i + 1] === '*') {
      const e = text.indexOf('*/', i + 2);
      i = e < 0 ? text.length : e + 1;
      out += ' ';
    } else if (c === '"' || c === "'" || c === '`') {
      let j = i + 1;
      while (j < text.length && text[j] !== c) j += text[j] === '\\' ? 2 : 1;
      out += c + c;
      i = j;
    } else out += c;
  }
  return out;
}

// The top-level keys of each object literal the first state() after `after` returns; a literal nested in another one, or built in a callback, is not counted.
export function stateKeys(text, after = '') {
  const from = text.indexOf(after);
  if (from < 0) return [];
  const code = jsCode(text.slice(from));
  const m = code.match(/function state\(\)(?:\s*:\s*\w+)?\s*\{/);
  if (!m) return [];
  const keys = new Set();
  const stack = [];
  let ret = -1;
  let prev = '';
  for (let i = m.index + m[0].length; i < code.length; i++) {
    const c = code[i];
    if (/\s/.test(c)) continue;
    if (/[A-Za-z_$]/.test(c)) {
      let j = i;
      while (j < code.length && /[\w$]/.test(code[j])) j++;
      const word = code.slice(i, j);
      if (word === 'return' && stack.every((s) => s.ch === '{' && !s.obj)) ret = stack.length;
      if (stack.at(-1)?.counted && (prev === '{' || prev === ',') && /^\s*[:,}]/.test(code.slice(j))) keys.add(word);
      prev = word;
      i = j - 1;
    } else if (c === '{' || c === '(' || c === '[') {
      const obj = c === '{' && (/^[(,:?[=]$/.test(prev) || prev === 'return');
      stack.push({ ch: c, obj, counted: obj && ret >= 0 && !stack.some((s) => s.obj) });
      prev = c;
    } else if (c === '}' || c === ')' || c === ']') {
      if (stack.length === 0) break;
      stack.pop();
      if (stack.length < ret) ret = -1;
      prev = c;
    } else {
      if (c === ';' && stack.length === ret) ret = -1;
      prev = c;
    }
  }
  return [...keys];
}

// A shell line's words from `s` up to its first operator, each raw and unquoted; an unclosed quote ends them.
function shellWords(s) {
  const words = [];
  let i = 0;
  for (;;) {
    while (s[i] === ' ' || s[i] === '\t') i++;
    if (i >= s.length || /[|&;()<>]/.test(s[i])) return words;
    let raw = '';
    let value = '';
    while (i < s.length && !/[\s|&;()<>]/.test(s[i])) {
      if (s[i] === "'") {
        const e = s.indexOf("'", i + 1);
        if (e < 0) return words;
        raw += s.slice(i, e + 1);
        value += s.slice(i + 1, e);
        i = e + 1;
      } else if (s[i] === '"') {
        let j = i + 1;
        while (j < s.length && s[j] !== '"') {
          if (s[j] === '\\' && /["$\\`]/.test(s[j + 1])) value += s[++j];
          else value += s[j];
          j++;
        }
        if (j >= s.length) return words;
        raw += s.slice(i, j + 1);
        i = j + 1;
      } else {
        raw += s[i];
        value += s[i++];
      }
    }
    words.push({ raw, value });
  }
}

// jq's program word among its arguments: the first that is no option and no --arg's name or value.
function jqProgram(words) {
  for (let k = 0; k < words.length; k++) {
    if (/^--(arg|argjson|slurpfile|rawfile)$/.test(words[k].value)) k += 2;
    else if (!words[k].value.startsWith('-')) return words[k];
  }
  return null;
}

// The fields a jq program reads off its input's top level: `.name` before the first `|` outside parens, not after a name, `.`, `]`, `)` or `?`.
export function jqFields(program) {
  const p = program.replace(/"(?:[^"\\]|\\.)*"/g, '""');
  const fields = [];
  let depth = 0;
  for (let i = 0; i < p.length; i++) {
    const c = p[i];
    if (c === '(') depth++;
    else if (c === ')') depth--;
    else if (c === '|' && depth === 0) break;
    else if (c === '.' && depth === 0 && !/[\w.\])?$]/.test(p[i - 1] ?? '')) {
      const m = p.slice(i + 1).match(/^[A-Za-z_]\w*/);
      if (m) fields.push(m[0]);
    }
  }
  return fields;
}

// Each jq program a script applies to a surface's state, as [line, surface, field]: piped straight from qs ipc call or dots-call, from a function that prints the state, or through a function that passes "$@" or "$1" to such a jq.
export function stateReads(text) {
  const lines = text.split('\n');
  const sources = new Map();
  const wrappers = new Map();
  const apps = (line) => {
    const names = [...sources.keys(), ...wrappers.keys()].join('|');
    const re = new RegExp(`(?<![\\w$-])(?:(?:qs ipc call|dots-call) (\\w+) state\\b${names ? `|(${names})(?![\\w(-])` : ''})`, 'g');
    const found = [];
    for (const m of line.matchAll(re)) {
      const rest = line.slice(m.index + m[0].length);
      if (m[2] && wrappers.has(m[2])) {
        const program = /^[ \t]/.test(rest) && jqProgram(shellWords(rest));
        if (program) found.push({ surface: wrappers.get(m[2]), program });
        continue;
      }
      const pipe = /^(?:\s+2>(?:\/dev\/null|&1))*\s*\|\s*jq\s+/.exec(rest);
      const program = pipe && jqProgram(shellWords(rest.slice(pipe[0].length)));
      if (program) found.push({ surface: m[1] ?? sources.get(m[2]), program });
    }
    return found;
  };
  for (let changed = true; changed; ) {
    changed = false;
    for (const line of lines) {
      const def = line.match(/^\s*(\w+)\(\)\s*\{(.*)\}\s*$/);
      if (!def || sources.has(def[1]) || wrappers.has(def[1])) continue;
      const src = def[2].match(/^\s*(?:timeout\s+\S+\s+)?(?:(?:qs ipc call|dots-call)\s+(\w+)\s+state|(\w+))(?:\s+2>\/dev\/null)?\s*;?\s*$/);
      const surface = src && (src[1] ?? sources.get(src[2]));
      const passed = apps(def[2]).find((a) => a.program.raw === '"$@"' || a.program.raw === '"$1"');
      if (surface) sources.set(def[1], surface);
      else if (passed) wrappers.set(def[1], passed.surface);
      changed ||= !!(surface || passed);
    }
  }
  const reads = [];
  lines.forEach((line, i) => {
    for (const a of apps(line)) for (const f of jqFields(a.program.value)) reads.push([i + 1, a.surface, f]);
  });
  return reads;
}

const surfaceKeys = () =>
  Object.fromEntries(
    Object.entries(stateSources).map(([s, files]) => [s, new Set(files.flatMap(([f, after]) => stateKeys(readFileSync(new URL(`../${f}`, import.meta.url), 'utf8'), after)))]),
  );

test("each mapped surface's state() yields its keys, the Control sections' among them", () => {
  const keys = surfaceKeys();
  for (const [s, k] of Object.entries(keys)) assert.ok(k.size >= 10, `${s} yields ${k.size} keys`);
  for (const k of ['calendar', 'fill', 'mode']) assert.ok(keys.island.has(k), `island.${k}`);
  for (const k of ['settled', 'cursorBox', 'panels', 'chargeLimit']) assert.ok(keys.control.has(k), `control.${k}`);
  for (const k of ['open', 'dnd', 'summaries']) assert.ok(keys.notifs.has(k), `notifs.${k}`);
  for (const k of ['fill', 'box', 'text', 'length']) assert.ok(!keys.control.has(k), `control has no nested ${k}`);
});

test('every first-level jq field a tests/dev script reads off a mapped surface\'s state is one its state() emits', () => {
  const keys = surfaceKeys();
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    for (const [n, s, k] of stateReads(readFileSync(dir + f, 'utf8'))) if (keys[s] && !keys[s].has(k)) found.push(`${f}:${n} ${s}.${k}`);
  }
  assert.deepEqual(found, []);
});

// The surfaces whose state() emits both .keyboard and .settled; a surface without them, the island's among them, is out of the open-then-type rule.
const keyed = 'launcher|control|notifs|goals|dns|accounts|tailscale|pass';

// m104's notif-rules.sh typed once niri listed the centre's layer Exclusive, a moment before the centre took the keys, so its s cycles read wrong. Each wtype after a line that opens a keyed surface must come after reads of both .keyboard and .settled, on one line or two, following helper calls; returns the wtype lines that do not.
export function typesBeforeKeys(text) {
  const lines = text.split('\n').map((raw) => {
    // Quoted text blanked to spaces, so positions still line up with the raw line, and a comment cut from both.
    const blank = raw.replace(/'[^']*'|"(?:[^"\\]|\\.)*"/g, (q) => q[0] + ' '.repeat(q.length - 2) + q[0]);
    const hash = blank.search(/(^|\s)#/);
    const end = hash < 0 ? raw.length : hash;
    return { raw: raw.slice(0, end), code: blank.slice(0, end), full: raw };
  });
  // Each function's body as [line index, text from] pairs: a one-line function's body starts past its opening brace.
  const bodies = new Map();
  const inBody = new Set();
  lines.forEach(({ code }, i) => {
    const one = code.match(/^\s*(\w+)\(\)\s*\{(?=.*\}\s*$)/);
    const many = code.match(/^(\s*)(\w+)\(\)\s*\{\s*$/);
    if (one) {
      bodies.set(one[1], [[i, one[0].length]]);
      inBody.add(i);
    } else if (many) {
      const close = lines.findIndex((l, j) => j > i && l.code === `${many[1]}}`);
      if (close < 0) return;
      const body = [];
      for (let j = i + 1; j < close; j++) body.push([j, 0]);
      bodies.set(many[2], body);
      for (let j = i; j <= close; j++) inBody.add(j);
    }
  });
  // The island shows one surface at a time, so opening one the rule leaves out, the cheat sheet say, puts the keyed one away as a close does.
  const surfaceCall = /(?:dots-call|qs ipc call)\s+(\w+)\s+(open|toggle|section|mode|close)\b/g;
  const isKeyed = new RegExp(`^(?:${keyed})$`);
  const calls = bodies.size ? new RegExp(`(?<![\\w$./-])(${[...bodies.keys()].join('|')})(?![\\w(-])`, 'g') : null;
  const memo = new Map();
  // A line's events in order, open, wait or type, with a helper call standing for its body's events.
  const events = ([i, from], seen) => {
    const raw = lines[i].raw.slice(from);
    const code = lines[i].code.slice(from);
    const found = [];
    for (const m of code.matchAll(surfaceCall)) {
      if (isKeyed.test(m[1])) found.push([m.index, m[2] === 'close' ? 'close' : 'open']);
      else if (m[2] !== 'close') found.push([m.index, 'close']);
    }
    // niri's .keyboard_interactivity is not the surface's .keyboard.
    for (const k of ['keyboard', 'settled']) for (const m of raw.matchAll(new RegExp(`\\.${k}(?!\\w)`, 'g'))) found.push([m.index, k]);
    // A check of the keys typed before the surface settles marks its wtype, which then stands for the wait.
    const early = /#\s*early on purpose\s*$/.test(lines[i].full);
    for (const m of code.matchAll(/(?<![\w-])wtype\b/g)) found.push([m.index, early ? 'early' : 'type']);
    for (const m of calls ? code.matchAll(calls) : []) {
      // `dots-call notifs open` names a surface, not a helper that happens to share its name.
      if (/(?:dots-call|qs ipc call)\s+$/.test(code.slice(0, m.index))) continue;
      for (const e of body(m[1], seen)) found.push([m.index, e]);
    }
    return found.sort((a, b) => a[0] - b[0]).map((e) => e[1]);
  };
  const body = (name, seen) => {
    if (seen.has(name)) return [];
    if (!memo.has(name)) memo.set(name, bodies.get(name).flatMap((at) => events(at, new Set(seen).add(name))));
    return memo.get(name);
  };
  const flagged = new Set();
  const scan = (at, seen) => {
    // The keys an open still waits on; a type while any is left is flagged.
    let unread = new Set();
    for (const a of at) {
      for (const e of events(a, seen)) {
        if (e === 'open') unread = new Set(['keyboard', 'settled']);
        else if (e === 'close' || e === 'early') unread = new Set();
        else if (e === 'type') unread.size && flagged.add(a[0] + 1);
        else unread.delete(e);
      }
    }
  };
  scan(
    lines.flatMap((_, i) => (inBody.has(i) ? [] : [[i, 0]])),
    new Set(),
  );
  for (const [name, at] of bodies) scan(at, new Set([name]));
  return [...flagged].sort((a, b) => a - b);
}

test('the open-then-type lint flags a wtype after an open that waited only on niri, and passes one that read .keyboard and .settled', () => {
  const m104 = `notifs() { timeout 0.5 qs ipc call notifs state 2>/dev/null; }
state_is() { notifs | jq -e "$@" >/dev/null; }
focus_is() { niri msg -j layers | jq -e '.[] | .keyboard_interactivity == "Exclusive"' >/dev/null; }
centre_open() { state_is '.open and .settled' && focus_is; }
niri msg action spawn -- dots-call notifs open
until_ok 3000 centre_open
wtype s
`;
  assert.deepEqual(typesBeforeKeys(m104), [7]);
  const fixed = m104.replace("'.open and .settled'", "'.open and .keyboard and .settled'");
  assert.deepEqual(typesBeforeKeys(fixed), []);
  assert.deepEqual(typesBeforeKeys(m104.replace("'.open and .settled'", "'.open and .keyboard'")), [7], 'the keyboard alone is not enough');
  // A helper that opens and one that waits are followed through their calls, on one line or many.
  const helpers = `open_acc() { niri msg action spawn -- dots-call accounts toggle; }
ready() {
  until_ok 3000 state_is '.open and .settled and .keyboard'
}
open_acc
wtype -k r
open_acc
ready
wtype -k r
`;
  assert.deepEqual(typesBeforeKeys(helpers), [6]);
  // The island's own state has no .keyboard, so typing after opening it is out of the rule.
  assert.deepEqual(typesBeforeKeys('niri msg action spawn -- dots-call island focus\nwtype -k d\n'), []);
  // The cheat sheet, opened over the launcher, replaces it in the island, and the launcher's close puts it away.
  assert.deepEqual(typesBeforeKeys('dots-call launcher toggle\ndots-call cheatsheet toggle\nwtype -k Escape\ndots-call launcher open\nqs ipc call launcher close\nwtype x\n'), []);
  // A check of the early keys themselves marks the wtype that types them.
  assert.deepEqual(typesBeforeKeys('dots-call launcher toggle\nwtype foot # early on purpose\nwtype -k Escape\n'), []);
  assert.deepEqual(typesBeforeKeys('dots-call launcher toggle\nwtype foot # early\nwtype -k Escape\n'), [2, 3]);
});

test('every tests/dev script reads a keyed surface\'s .keyboard and .settled after opening it and before it types', () => {
  const found = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
    for (const n of typesBeforeKeys(readFileSync(dir + f, 'utf8'))) found.push(`${f}:${n}`);
  }
  assert.deepEqual(found, [], "wait with until_ok <ms> on a state read of '.keyboard and .settled'");
});

// QML with its comments blanked, as `code`, and with string contents blanked too, as `shape`, both the length of the text so a position in one is the position in the other.
function qmlScan(text) {
  let code = '';
  let shape = '';
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '/' && (text[i + 1] === '/' || text[i + 1] === '*')) {
      const e = text[i + 1] === '/' ? text.indexOf('\n', i) : text.indexOf('*/', i + 2) + 2;
      const end = e <= i + 1 ? text.length : e;
      const gap = text.slice(i, end).replace(/[^\n]/g, ' ');
      code += gap;
      shape += gap;
      i = end - 1;
    } else if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < text.length && text[j] !== c && text[j] !== '\n') j += text[j] === '\\' ? 2 : 1;
      code += text.slice(i, j + 1);
      shape += c + ' '.repeat(Math.max(0, j - i - 1)) + c;
      i = j;
    } else {
      code += c;
      shape += c;
    }
  }
  return { code, shape };
}

// Whether a QML file calls theme.notice(, whoever's theme it is.
const callsNotice = (text) => /\btheme\.notice\(/.test(qmlScan(text).shape);

// A file that calls theme.notice( must draw the notice: a Root.ToolNote, or a handler for the signal (function onNotice) that puts its text somewhere drawn.
export function noticeUndrawn(text) {
  const { code } = qmlScan(text);
  return callsNotice(text) && !/\bRoot\.ToolNote\b/.test(code) && !/\bfunction onNotice\(/.test(code);
}

// Whether the file names an item objectName: "card" that fills its parent (anchors.fill: parent, or width: parent.width with a height of its own), or is the root itself, which the island sizes to fit.
export function hasFillingCard(text) {
  const { code, shape } = qmlScan(text);
  const root = shape.indexOf('{');
  for (const m of code.matchAll(/\bobjectName:\s*"card"/g)) {
    let open = -1;
    for (let i = m.index, depth = 0; i >= 0; i--) {
      if (shape[i] === '}') depth++;
      else if (shape[i] === '{' && depth-- === 0) {
        open = i;
        break;
      }
    }
    if (open < 0) continue;
    if (open === root) return true;
    // The card's own properties: what sits at its brace depth, not in a child's block.
    let own = '';
    for (let i = open + 1, depth = 0; i < shape.length && depth >= 0; i++) {
      if (shape[i] === '{') depth++;
      else if (shape[i] === '}') depth--;
      else if (depth === 0) own += code[i];
    }
    if (/\banchors\.fill:\s*parent\b|\bwidth:\s*parent\.width\b/.test(own)) return true;
  }
  return false;
}

// The name and file of each surface in Surfaces.qml's islandSurfaces and takeovers lists, the file read off the Loader the name's property points at; takeovers may be absent.
export function surfaceFiles(text) {
  const found = [];
  for (const list of ['islandSurfaces', 'takeovers']) {
    const names = text.match(new RegExp(`readonly property var ${list}: \\[([^\\]]*)\\]`));
    for (const name of names?.[1].split(',').map((n) => n.trim()).filter(Boolean) ?? []) {
      const loader = text.match(new RegExp(`readonly property var ${name}: (\\w+)\\.item`))?.[1];
      const at = loader ? text.indexOf(`id: ${loader}\n`) : -1;
      const file = at < 0 ? null : text.slice(at).match(/sourceComponent:\s*Root\.(\w+)/)?.[1];
      assert.ok(file, `${list} names ${name}, which no Loader's sourceComponent gives a file`);
      found.push([name, `${file}.qml`]);
    }
  }
  return found;
}

// m105's Pass, Tailscale and Accounts called theme.notice() while open and nothing drew it, because the island draws the surface, not the notice. A surface that calls it carries a ToolNote, or handles the signal itself.
test('the notice lint flags a surface that calls theme.notice and draws nothing, and passes one with a ToolNote or an onNotice handler', () => {
  const bare = 'Item {\n  Process { onExited: panel.theme.notice("done") }\n}\n';
  assert.equal(noticeUndrawn(bare), true);
  assert.equal(noticeUndrawn(bare.replace('Item {', 'Item {\n  Root.ToolNote { theme: panel.theme }')), false);
  assert.equal(noticeUndrawn(bare.replace('Item {', 'Item {\n  Connections { target: panel.theme\n function onNotice(text) { line.text = text } }')), false);
  // A comment or a string that names the call is not a call, and a file that never calls it has nothing to draw.
  assert.equal(noticeUndrawn('Item {\n  // calls theme.notice(text) later\n  Text { text: "theme.notice(x)" }\n}\n'), false);
  assert.equal(noticeUndrawn('Item {\n  Root.ToolNote { theme: panel.theme }\n}\n'), false);
});

// Root.Surface used to carry objectName "card"; three tools lost it in the move and any press off a row closed them.
test('the card lint wants an item named card that fills its parent, or the root itself', () => {
  assert.equal(hasFillingCard('Item {\n  Item {\n    objectName: "card"\n    anchors.fill: parent\n  }\n}\n'), true);
  assert.equal(hasFillingCard('Item {\n  Item {\n    id: card\n    objectName: "card"\n    width: parent.width\n    height: column.implicitHeight + 32\n  }\n}\n'), true);
  assert.equal(hasFillingCard('Item {\n  objectName: "card"\n  Text {}\n}\n'), true);
  assert.equal(hasFillingCard('Item {\n  Text {}\n}\n'), false);
  assert.equal(hasFillingCard('Item {\n  Item {\n    objectName: "card"\n    x: 16\n    width: 40\n  }\n}\n'), false);
  // The fill belongs to the card's own item, not to a child inside it, and a comment is no card.
  assert.equal(hasFillingCard('Item {\n  Item {\n    objectName: "card"\n    Item { anchors.fill: parent }\n  }\n}\n'), false);
  assert.equal(hasFillingCard('Item {\n  // objectName: "card"\n  Item { anchors.fill: parent }\n}\n'), false);
});

test('surfaceFiles maps the names in islandSurfaces and takeovers to their Loaders\' files, and takes a tree without takeovers', () => {
  const qml = `
    readonly property var pass: passLoader.item
    readonly property var picker: pickerLoader.item
    readonly property var islandSurfaces: [pass]
    Loader {
        id: passLoader
        sourceComponent: Root.Pass {
        }
    }
    Loader {
        id: pickerLoader
        sourceComponent: Root.FilePicker {
        }
    }
`;
  assert.deepEqual(surfaceFiles(qml), [['pass', 'Pass.qml']]);
  assert.deepEqual(surfaceFiles(qml.replace('[pass]', '[pass]\n    readonly property var takeovers: [picker]')), [['pass', 'Pass.qml'], ['picker', 'FilePicker.qml']]);
});

// The files of the surfaces the island or a takeover draws, read from Surfaces.qml, as [name, file, text].
const drawnSurfaces = () => {
  const found = surfaceFiles(readFileSync(new URL('../Surfaces.qml', import.meta.url), 'utf8'));
  assert.ok(found.length >= 10, `${found.length} surfaces mapped`);
  return found.map(([name, file]) => [`${name} (${file})`, readFileSync(new URL(`../${file}`, import.meta.url), 'utf8')]);
};

test('every island surface and takeover that calls theme.notice draws it', () => {
  assert.deepEqual(drawnSurfaces().filter(([, text]) => noticeUndrawn(text)).map(([n]) => n), [], 'add Root.ToolNote { theme: ... } at the tool\'s foot');
});

test('every island surface and takeover that calls theme.notice names a card that fills it', () => {
  assert.deepEqual(drawnSurfaces().filter(([, text]) => callsNotice(text) && !hasFillingCard(text)).map(([n]) => n), [], 'name an item objectName: "card" with anchors.fill: parent');
});

// A prompt that takes the island over holds another process's request, and a press the surfaces' window reads as outside it cancels that request, so every takeover names a card that fills it, notice or not.
test('every takeover names a card that fills it', () => {
  const text = readFileSync(new URL('../Surfaces.qml', import.meta.url), 'utf8');
  const takeovers = surfaceFiles(text).filter(([name]) => new RegExp(`readonly property var takeovers: \\[[^\\]]*\\b${name}\\b`).test(text));
  assert.ok(takeovers.length >= 1, 'Surfaces.qml lists its takeovers');
  const bare = takeovers.filter(([, file]) => !hasFillingCard(readFileSync(new URL(`../${file}`, import.meta.url), 'utf8')));
  assert.deepEqual(bare.map(([n, f]) => `${n} (${f})`), [], 'name an item objectName: "card" with anchors.fill: parent');
});

// m106 moved the last cards into the island: nothing in the shell's surfaces window is a card, so no veil (a wash of paper over the output), no card theme and no card-open state are left (3QDRPW73).
test('the surfaces window holds no card host and no veil', () => {
  const text = readFileSync(new URL('../Surfaces.qml', import.meta.url), 'utf8');
  const files = ['Surfaces.qml', 'Island.qml', 'Surface.qml', 'lib/surface.mjs'].concat(surfaceFiles(text).map(([, f]) => f));
  const found = [];
  for (const f of new Set(files)) {
    const code = jsCode(readFileSync(new URL(`../${f}`, import.meta.url), 'utf8'));
    for (const name of ['panelTheme', 'cardOpen', 'wash']) if (new RegExp(`\\b${name}\\b`).test(code)) found.push(`${f}: ${name}`);
  }
  assert.deepEqual(found, []);
});
