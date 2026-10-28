import { test } from 'node:test';
import assert from 'node:assert/strict';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
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
