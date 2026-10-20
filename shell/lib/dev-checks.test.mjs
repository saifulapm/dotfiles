import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';

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
