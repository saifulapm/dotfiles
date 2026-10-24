import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { report, switchCycle, BUDGETS } from './bench.mjs';

const cli = new URL('./bench.mjs', import.meta.url).pathname;
const good = { firstFrameMs: 130, rssKiB: 152576, coldMs: 48, warmMs: 4, pickerColdMs: 41, pickerWarmMs: 9, passColdMs: 37, filesColdMs: 33, appFirstFrameMs: 310, appRssKiB: 180224, appLeft: 0, dekhoFirstFrameMs: 180, dekhoRssKiB: 131072, dekhoLeft: 0, deenFirstFrameMs: 220, deenRssKiB: 141072, deenLeft: 0, timers: 1, switchMs: 120, switchedKiB: 157000, anonShmemKiB: 236544, cpu: '0.03' };

test('every measure within budget reads ok and passes', () => {
  const r = report(good, BUDGETS);
  assert.equal(r.over, false);
  assert.deepEqual(r.lines, [
    'first frame   130 ms  ≤ 150 ms   ok',
    'idle rss      149 MiB ≤ 200 MiB  ok',
    'cgroup mem    231 MiB',
    'panel cold    48 ms   ≤ 50 ms    ok',
    'panel warm    4 ms    ≤ 16 ms    ok',
    'picker cold   41 ms   ≤ 50 ms    ok',
    'picker warm   9 ms    ≤ 16 ms    ok',
    'pass cold     37 ms   ≤ 50 ms    ok',
    'files cold    33 ms   ≤ 50 ms    ok',
    'timers        1       = 1        ok',
    'theme switch  120 ms  ≤ 300 ms   ok',
    'idle cpu      0.03 %  ≤ 0.07 %   ok',
    'app 1st frame 310 ms  ≤ 500 ms   ok',
    'app open rss  176 MiB ≤ 250 MiB  ok',
    'app closed    0 left  = 0 left   ok',
    'dekho frame   180 ms  ≤ 500 ms   ok',
    'dekho rss     128 MiB ≤ 250 MiB  ok',
    'dekho closed  0 left  = 0 left   ok',
    'deen frame    220 ms  ≤ 500 ms   ok',
    'deen rss      137 MiB ≤ 250 MiB  ok',
    'deen closed   0 left  = 0 left   ok',
    'rss switched  153 MiB',
  ]);
});

test('one measure over its budget reads OVER and fails', () => {
  const r = report({ ...good, warmMs: 17 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[4], 'panel warm    17 ms   ≤ 16 ms    OVER');
});

test('a first frame of 150 ms passes and 160 ms is OVER', () => {
  assert.equal(report({ ...good, firstFrameMs: 150 }, BUDGETS).over, false);
  assert.equal(report({ ...good, firstFrameMs: 160 }, BUDGETS).over, true);
});

test('RSS a KiB over the 200 MiB budget is OVER, not rounded down into it', () => {
  assert.equal(report({ ...good, rssKiB: 200 * 1024 }, BUDGETS).over, false);
  assert.equal(report({ ...good, rssKiB: 200 * 1024 + 1 }, BUDGETS).over, true);
});

// Pass loads on open and unloads 30 s after it closes, so its first open after that answers to the cold budget.
test('a first open of Pass after its unload over 50 ms is OVER', () => {
  const r = report({ ...good, passColdMs: 51 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[7], 'pass cold     51 ms   ≤ 50 ms    OVER');
});

// The file picker loads on a request and unloads 30 s after it closes, so its first open after that answers to the cold budget too.
test('a first open of the file picker after its unload over 50 ms is OVER', () => {
  const r = report({ ...good, filesColdMs: 51 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[8], 'files cold    51 ms   ≤ 50 ms    OVER');
});

test('a timer count other than the budget is OVER either way', () => {
  assert.equal(report({ ...good, timers: 0 }, BUDGETS).over, true);
  assert.equal(report({ ...good, timers: 2 }, BUDGETS).over, true);
});

test('the CLI exits 1 when an env budget is exceeded and 0 otherwise', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03', '120', '157000', '236544', '41', '9', '37', '33', '310', '180224', '0', '180', '131072', '0', '220', '141072', '0'];
  assert.match(execFileSync('node', [cli, ...args], { encoding: 'utf8' }), /panel warm {4}4 ms/);
  assert.throws(
    () => execFileSync('node', [cli, ...args], { env: { ...process.env, DOTS_BUDGET_FIRST_FRAME_MS: '1' }, stdio: 'pipe' }),
    (e) => e.status === 1 && /first frame +130 ms +≤ 1 ms +OVER/.test(e.stdout.toString()),
  );
});

test('the slowest of the six theme switches over 300 ms is OVER', () => {
  const r = report({ ...good, switchMs: 301 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[10], 'theme switch  301 ms  ≤ 300 ms   OVER');
});

test('the six ordered pairs of three themes are each switched once, ending where they began', () => {
  const steps = switchCycle(['paper', 'artboard', 'blueprint'], 'paper');
  assert.deepEqual(steps, ['artboard', 'blueprint', 'paper', 'blueprint', 'artboard', 'paper']);
  const pairs = steps.map((to, i) => `${i ? steps[i - 1] : 'paper'}>${to}`);
  assert.equal(new Set(pairs).size, 6);
});

test('the RSS after every theme has been shown is reported but never OVER', () => {
  assert.equal(report({ ...good, switchedKiB: 400 * 1024 }, BUDGETS).over, false);
});

test('idle cpu over 0.07 % is OVER', () => {
  const r = report({ ...good, cpu: '0.08' }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[11], 'idle cpu      0.08 %  ≤ 0.07 %   OVER');
});

test('the cgroup anon+shmem is reported beside idle rss but never OVER', () => {
  const r = report({ ...good, anonShmemKiB: 900 * 1024 }, BUDGETS);
  assert.equal(r.lines[2], 'cgroup mem    900 MiB');
  assert.equal(r.over, false);
});

test('the CLI prints the cgroup memory from its ninth argument', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03', '120', '157000', '236544', '41', '9', '37', '33', '310', '180224', '0', '180', '131072', '0', '220', '141072', '0'];
  assert.match(execFileSync('node', [cli, ...args], { encoding: 'utf8' }), /cgroup mem {4}231 MiB/);
});

test('a picker cold of 51 ms is OVER and 50 ok, a picker warm of 17 ms is OVER and 16 ok', () => {
  assert.equal(report({ ...good, pickerColdMs: 50 }, BUDGETS).over, false);
  const cold = report({ ...good, pickerColdMs: 51 }, BUDGETS);
  assert.equal(cold.over, true);
  assert.equal(cold.lines[5], 'picker cold   51 ms   ≤ 50 ms    OVER');
  assert.equal(report({ ...good, pickerWarmMs: 16 }, BUDGETS).over, false);
  const warm = report({ ...good, pickerWarmMs: 17 }, BUDGETS);
  assert.equal(warm.over, true);
  assert.equal(warm.lines[6], 'picker warm   17 ms   ≤ 16 ms    OVER');
});

test('the CLI prints both picker lines from its tenth and eleventh arguments and exits 1 when either is over', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03', '120', '157000', '236544'];
  const out = execFileSync('node', [cli, ...args, '41', '9', '37', '33', '310', '180224', '0', '180', '131072', '0', '220', '141072', '0'], { encoding: 'utf8' });
  assert.match(out, /picker cold {3}41 ms +≤ 50 ms +ok/);
  assert.match(out, /picker warm {3}9 ms +≤ 16 ms +ok/);
  for (const [c, w] of [['51', '9'], ['41', '17']]) {
    assert.throws(
      () => execFileSync('node', [cli, ...args, c, w, '37', '33', '310', '180224', '0', '180', '131072', '0', '220', '141072', '0'], { stdio: 'pipe' }),
      (e) => e.status === 1 && /OVER/.test(e.stdout.toString()),
    );
  }
});

test('the CLI prints pass cold from its twelfth argument', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03', '120', '157000', '236544', '41', '9', '37', '33', '310', '180224', '0', '180', '131072', '0', '220', '141072', '0'];
  assert.match(execFileSync('node', [cli, ...args], { encoding: 'utf8' }), /pass cold {5}37 ms +≤ 50 ms +ok/);
});

test('the CLI prints files cold from its thirteenth argument', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03', '120', '157000', '236544', '41', '9', '37', '33', '310', '180224', '0', '180', '131072', '0', '220', '141072', '0'];
  assert.match(execFileSync('node', [cli, ...args], { encoding: 'utf8' }), /files cold {4}33 ms +≤ 50 ms +ok/);
});

// Files is its own qs process: its first frame is held to 500 ms, its RSS to 250 MiB, and nothing of it may outlive its window.
test('an App first frame of 501 ms is OVER and 500 ok', () => {
  assert.equal(report({ ...good, appFirstFrameMs: 500 }, BUDGETS).over, false);
  const r = report({ ...good, appFirstFrameMs: 501 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[12], 'app 1st frame 501 ms  ≤ 500 ms   OVER');
});

test('an App open RSS a KiB over 250 MiB is OVER and 250 MiB ok', () => {
  assert.equal(report({ ...good, appRssKiB: 250 * 1024 }, BUDGETS).over, false);
  const r = report({ ...good, appRssKiB: 250 * 1024 + 1 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[13], 'app open rss  250 MiB ≤ 250 MiB  OVER');
});

test('one App process left after its window closes is OVER and none is ok', () => {
  assert.equal(report({ ...good, appLeft: 0 }, BUDGETS).over, false);
  const r = report({ ...good, appLeft: 1 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[14], 'app closed    1 left  = 0 left   OVER');
});

test('the CLI prints the App lines from its fourteenth to sixteenth arguments and exits 1 when one is over', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03', '120', '157000', '236544', '41', '9', '37', '33'];
  const dekho = ['180', '131072', '0', '220', '141072', '0'];
  assert.match(execFileSync('node', [cli, ...args, '310', '180224', '0', ...dekho], { encoding: 'utf8' }), /app 1st frame 310 ms +≤ 500 ms +ok/);
  for (const tail of [['501', '180224', '0'], ['310', String(250 * 1024 + 1), '0'], ['310', '180224', '1']]) {
    assert.throws(
      () => execFileSync('node', [cli, ...args, ...tail, ...dekho], { stdio: 'pipe' }),
      (e) => e.status === 1 && /app .*OVER/.test(e.stdout.toString()),
    );
  }
});

// Dekho is a second App, held to the same budgets as Files and reported on its own lines.
test('Dekho over any App budget reads OVER on its own line', () => {
  assert.equal(report({ ...good, dekhoFirstFrameMs: 500, dekhoRssKiB: 250 * 1024, dekhoLeft: 0 }, BUDGETS).over, false);
  assert.equal(report({ ...good, dekhoFirstFrameMs: 501 }, BUDGETS).lines[15], 'dekho frame   501 ms  ≤ 500 ms   OVER');
  assert.equal(report({ ...good, dekhoRssKiB: 250 * 1024 + 1 }, BUDGETS).lines[16], 'dekho rss     250 MiB ≤ 250 MiB  OVER');
  assert.equal(report({ ...good, dekhoLeft: 1 }, BUDGETS).lines[17], 'dekho closed  1 left  = 0 left   OVER');
});

test('the CLI reads Dekho from its seventeenth to nineteenth arguments and exits 1 when one is over', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03', '120', '157000', '236544', '41', '9', '37', '33', '310', '180224', '0'];
  const deen = ['220', '141072', '0'];
  assert.match(execFileSync('node', [cli, ...args, '180', '131072', '0', ...deen], { encoding: 'utf8' }), /dekho frame +180 ms +≤ 500 ms +ok/);
  for (const tail of [['501', '131072', '0'], ['180', String(250 * 1024 + 1), '0'], ['180', '131072', '1']]) {
    assert.throws(
      () => execFileSync('node', [cli, ...args, ...tail, ...deen], { stdio: 'pipe' }),
      (e) => e.status === 1 && /dekho .*OVER/.test(e.stdout.toString()),
    );
  }
});

// Deen is a third App, held to the same budgets and reported on its own lines.
test('Deen over any App budget reads OVER on its own line', () => {
  assert.equal(report({ ...good, deenFirstFrameMs: 500, deenRssKiB: 250 * 1024, deenLeft: 0 }, BUDGETS).over, false);
  assert.equal(report({ ...good, deenFirstFrameMs: 501 }, BUDGETS).lines[18], 'deen frame    501 ms  ≤ 500 ms   OVER');
  assert.equal(report({ ...good, deenRssKiB: 250 * 1024 + 1 }, BUDGETS).lines[19], 'deen rss      250 MiB ≤ 250 MiB  OVER');
  assert.equal(report({ ...good, deenLeft: 1 }, BUDGETS).lines[20], 'deen closed   1 left  = 0 left   OVER');
});

test('the CLI reads Deen from its twentieth to twenty-second arguments and exits 1 when one is over', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03', '120', '157000', '236544', '41', '9', '37', '33', '310', '180224', '0', '180', '131072', '0'];
  assert.match(execFileSync('node', [cli, ...args, '220', '141072', '0'], { encoding: 'utf8' }), /deen frame +220 ms +≤ 500 ms +ok/);
  for (const tail of [['501', '141072', '0'], ['220', String(250 * 1024 + 1), '0'], ['220', '141072', '1']]) {
    assert.throws(
      () => execFileSync('node', [cli, ...args, ...tail], { stdio: 'pipe' }),
      (e) => e.status === 1 && /deen .*OVER/.test(e.stdout.toString()),
    );
  }
});
