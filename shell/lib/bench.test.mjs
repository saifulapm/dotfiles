import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { report, switchCycle, limits, frameStats, morphIntervals, BUDGETS, BASELINE, SPREAD } from './bench.mjs';

const cli = new URL('./bench.mjs', import.meta.url).pathname;
const good = { firstFrameMs: 130, rssKiB: 152576, coldMs: 38, warmMs: 4, schemesColdMs: 35, schemesWarmMs: 9, passColdMs: 3, filesColdMs: 11, appFirstFrameMs: 310, appRssKiB: 180224, appLeft: 0, dekhoFirstFrameMs: 180, dekhoRssKiB: 131072, dekhoLeft: 0, deenFirstFrameMs: 220, deenRssKiB: 141072, deenLeft: 0, timers: 1, switchMs: 120, switchedKiB: 157000, anonShmemKiB: 236544, cpu: '0.03', morphOpen: { max: 14, p95: 9 }, morphClose: { max: 15, p95: 10 }, morphSwitch: { max: 17, p95: 8 } };
const rest = ['180224', '0', '180', '131072', '0', '220', '141072', '0'];
const head = ['130', '152576', '38', '4', '1', '0.03', '120', '157000', '236544', '35', '9', '3', '11', '310'];
const morph = ['14', '9', '15', '10', '17', '8'];
const args = [...head, ...rest];

test('the limits are the budget or the baseline plus its spread, whichever holds a row tighter', () => {
  assert.deepEqual(limits(BUDGETS, BASELINE, SPREAD), {
    firstFrameMs: 180,
    rssMiB: 204,
    idleCpu: 0.15,
    switchMs: 131,
    coldMs: 50,
    warmMs: 16,
    schemesColdMs: 50,
    schemesWarmMs: 16,
    passColdMs: 20,
    filesColdMs: 28,
  });
});

test('every measure within its limit reads ok and passes', () => {
  const r = report(good, BUDGETS);
  assert.equal(r.over, false);
  assert.deepEqual(r.lines, [
    'first frame   130 ms  ≤ 180 ms   ok',
    'idle rss      149 MiB ≤ 204 MiB  ok',
    'cgroup mem    231 MiB',
    'panel cold    38 ms   ≤ 50 ms    ok',
    'panel warm    4 ms    ≤ 16 ms    ok',
    'c mode cold   35 ms   ≤ 50 ms    ok',
    'c mode warm   9 ms    ≤ 16 ms    ok',
    'pass cold     3 ms    ≤ 20 ms    ok',
    'files cold    11 ms   ≤ 28 ms    ok',
    'timers        1       = 1        ok',
    'theme switch  120 ms  ≤ 131 ms   ok',
    'idle cpu      0.03 %  ≤ 0.15 %   ok',
    'app 1st frame 310 ms  ≤ 500 ms   ok',
    'app open rss  176 MiB ≤ 250 MiB  ok',
    'app closed    0 left  = 0 left   ok',
    'dekho frame   180 ms  ≤ 500 ms   ok',
    'dekho rss     128 MiB ≤ 250 MiB  ok',
    'dekho closed  0 left  = 0 left   ok',
    'deen frame    220 ms  ≤ 500 ms   ok',
    'deen rss      137 MiB ≤ 250 MiB  ok',
    'deen closed   0 left  = 0 left   ok',
    'morph open    14/9 ms ≤ 36/12 ms ok',
    'morph close   15/10 ms ≤ 36/12 ms ok',
    'morph switch  17/8 ms ≤ 20/12 ms ok',
    'rss switched  153 MiB',
  ]);
});

test('one measure over its budget reads OVER and fails', () => {
  const r = report({ ...good, warmMs: 17 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[4], 'panel warm    17 ms   ≤ 16 ms    OVER');
});

test('a first frame of 180 ms passes and 181 ms is OVER', () => {
  assert.equal(report({ ...good, firstFrameMs: 180 }, BUDGETS).over, false);
  assert.equal(report({ ...good, firstFrameMs: 181 }, BUDGETS).over, true);
});

test('RSS a KiB over the 204 MiB baseline is OVER, not rounded down into it', () => {
  assert.equal(report({ ...good, rssKiB: 204 * 1024 }, BUDGETS).over, false);
  assert.equal(report({ ...good, rssKiB: 204 * 1024 + 1 }, BUDGETS).over, true);
});

test('idle cpu of 0.15 % passes and 0.16 % is OVER', () => {
  assert.equal(report({ ...good, cpu: '0.15' }, BUDGETS).over, false);
  const r = report({ ...good, cpu: '0.16' }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[11], 'idle cpu      0.16 %  ≤ 0.15 %   OVER');
});

test('a theme switch of 131 ms passes and 132 ms is OVER', () => {
  assert.equal(report({ ...good, switchMs: 131 }, BUDGETS).over, false);
  const r = report({ ...good, switchMs: 132 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[10], 'theme switch  132 ms  ≤ 131 ms   OVER');
});

test('a panel cold of 50 ms passes and 51 ms is OVER', () => {
  assert.equal(report({ ...good, coldMs: 50 }, BUDGETS).over, false);
  const r = report({ ...good, coldMs: 51 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[3], 'panel cold    51 ms   ≤ 50 ms    OVER');
});

// Pass loads on open and unloads 30 s after it closes; its first open after that is held to its baseline plus the spread.
test('a first open of Pass after its unload over 20 ms is OVER', () => {
  assert.equal(report({ ...good, passColdMs: 20 }, BUDGETS).over, false);
  const r = report({ ...good, passColdMs: 21 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[7], 'pass cold     21 ms   ≤ 20 ms    OVER');
});

// The file picker loads on a request and unloads 30 s after it closes, so its first open after that is held the same way.
test('a first open of the file picker after its unload over 28 ms is OVER', () => {
  assert.equal(report({ ...good, filesColdMs: 28 }, BUDGETS).over, false);
  const r = report({ ...good, filesColdMs: 29 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[8], 'files cold    29 ms   ≤ 28 ms    OVER');
});

test('a timer count other than the budget is OVER either way', () => {
  assert.equal(report({ ...good, timers: 0 }, BUDGETS).over, true);
  assert.equal(report({ ...good, timers: 2 }, BUDGETS).over, true);
});

test('the CLI exits 0 when every row is ok and 1 when one is over', () => {
  assert.match(execFileSync('node', [cli, ...args, ...morph], { encoding: 'utf8' }), /panel warm {4}4 ms/);
  assert.throws(
    () => execFileSync('node', [cli, ...args, ...morph], { env: { ...process.env, DOTS_BUDGET_APP_FIRST_FRAME_MS: '1' }, stdio: 'pipe' }),
    (e) => e.status === 1 && /app 1st frame 310 ms +≤ 1 ms +OVER/.test(e.stdout.toString()),
  );
  const over = [...head.slice(0, 2), '51', ...head.slice(3), ...rest, ...morph];
  assert.throws(
    () => execFileSync('node', [cli, ...over], { stdio: 'pipe' }),
    (e) => e.status === 1 && /panel cold {4}51 ms +≤ 50 ms +OVER/.test(e.stdout.toString()),
  );
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

test('the cgroup anon+shmem is reported beside idle rss but never OVER', () => {
  const r = report({ ...good, anonShmemKiB: 900 * 1024 }, BUDGETS);
  assert.equal(r.lines[2], 'cgroup mem    900 MiB');
  assert.equal(r.over, false);
});

test('the CLI prints the cgroup memory from its ninth argument', () => {
  assert.match(execFileSync('node', [cli, ...args, ...morph], { encoding: 'utf8' }), /cgroup mem {4}231 MiB/);
});

test('a c mode cold of 51 ms is OVER and 50 ok, a c mode warm of 17 ms is OVER and 16 ok', () => {
  assert.equal(report({ ...good, schemesColdMs: 50 }, BUDGETS).over, false);
  const cold = report({ ...good, schemesColdMs: 51 }, BUDGETS);
  assert.equal(cold.over, true);
  assert.equal(cold.lines[5], 'c mode cold   51 ms   ≤ 50 ms    OVER');
  assert.equal(report({ ...good, schemesWarmMs: 16 }, BUDGETS).over, false);
  const warm = report({ ...good, schemesWarmMs: 17 }, BUDGETS);
  assert.equal(warm.over, true);
  assert.equal(warm.lines[6], 'c mode warm   17 ms   ≤ 16 ms    OVER');
});

test('the CLI prints both c mode lines from its tenth and eleventh arguments and exits 1 when either is over', () => {
  const out = execFileSync('node', [cli, ...args, ...morph], { encoding: 'utf8' });
  assert.match(out, /c mode cold {3}35 ms +≤ 50 ms +ok/);
  assert.match(out, /c mode warm {3}9 ms +≤ 16 ms +ok/);
  for (const [c, w] of [['51', '9'], ['35', '17']]) {
    const a = [...head.slice(0, 9), c, w, ...head.slice(11), ...rest, ...morph];
    assert.throws(
      () => execFileSync('node', [cli, ...a], { stdio: 'pipe' }),
      (e) => e.status === 1 && /OVER/.test(e.stdout.toString()),
    );
  }
});

test('the CLI prints pass cold from its twelfth argument', () => {
  assert.match(execFileSync('node', [cli, ...args, ...morph], { encoding: 'utf8' }), /pass cold {5}3 ms +≤ 20 ms +ok/);
});

test('the CLI prints files cold from its thirteenth argument', () => {
  assert.match(execFileSync('node', [cli, ...args, ...morph], { encoding: 'utf8' }), /files cold {4}11 ms +≤ 28 ms +ok/);
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
  const dekho = rest.slice(3);
  assert.match(execFileSync('node', [cli, ...args, ...morph], { encoding: 'utf8' }), /app 1st frame 310 ms +≤ 500 ms +ok/);
  for (const tail of [['501', '180224', '0'], ['310', String(250 * 1024 + 1), '0'], ['310', '180224', '1']]) {
    assert.throws(
      () => execFileSync('node', [cli, ...head.slice(0, 13), ...tail, ...dekho, ...morph], { stdio: 'pipe' }),
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
  const deen = rest.slice(5);
  assert.match(execFileSync('node', [cli, ...args, ...morph], { encoding: 'utf8' }), /dekho frame +180 ms +≤ 500 ms +ok/);
  for (const tail of [['501', '131072', '0'], ['180', String(250 * 1024 + 1), '0'], ['180', '131072', '1']]) {
    assert.throws(
      () => execFileSync('node', [cli, ...head, ...rest.slice(0, 3), ...tail, ...deen, ...morph], { stdio: 'pipe' }),
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
  assert.match(execFileSync('node', [cli, ...args, ...morph], { encoding: 'utf8' }), /deen frame +220 ms +≤ 500 ms +ok/);
  for (const tail of [['501', '141072', '0'], ['220', String(250 * 1024 + 1), '0'], ['220', '141072', '1']]) {
    assert.throws(
      () => execFileSync('node', [cli, ...head, ...rest.slice(0, 5), ...tail, ...morph], { stdio: 'pipe' }),
      (e) => e.status === 1 && /deen .*OVER/.test(e.stdout.toString()),
    );
  }
});

test('frameStats gives the longest interval and the nearest-rank 95th percentile', () => {
  const twenty = Array.from({ length: 20 }, (_, i) => i + 1);
  assert.deepEqual(frameStats(twenty), { max: 20, p95: 19 });
  assert.deepEqual(frameStats([7, 3, 5]), { max: 7, p95: 7 });
  assert.deepEqual(frameStats([16]), { max: 16, p95: 16 });
  assert.equal(frameStats([]), null);
});

// JN450PWP and S7XQGGT4: one missed 60 Hz refresh at most, plus 2 ms of the shell's whole-ms clock, so the longest gap is held to 36 ms; each frame's work to 12 ms at p95.
test('a morph open with a longest interval of 37 ms or a p95 of 13 ms is OVER, 36 and 12 ok', () => {
  assert.equal(report({ ...good, morphOpen: { max: 36, p95: 12 } }, BUDGETS).over, false);
  const long = report({ ...good, morphOpen: { max: 37, p95: 9 } }, BUDGETS);
  assert.equal(long.over, true);
  assert.equal(long.lines[21], 'morph open    37/9 ms ≤ 36/12 ms OVER');
  const slow = report({ ...good, morphOpen: { max: 14, p95: 13 } }, BUDGETS);
  assert.equal(slow.over, true);
  assert.equal(slow.lines[21], 'morph open    14/13 ms ≤ 36/12 ms OVER');
});

test('a morph close is held to the same budgets on its own line', () => {
  assert.equal(report({ ...good, morphClose: { max: 36, p95: 12 } }, BUDGETS).over, false);
  const r = report({ ...good, morphClose: { max: 37, p95: 12 } }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[22], 'morph close   37/12 ms ≤ 36/12 ms OVER');
});

test('a morph that was not timed reads none and is OVER', () => {
  const r = report({ ...good, morphOpen: null }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[21], 'morph open    none');
});

test('the CLI reads the morph rows from its last six arguments and counts a missing pair as OVER', () => {
  const out = execFileSync('node', [cli, ...args, ...morph], { encoding: 'utf8' });
  assert.match(out, /morph open {4}14\/9 ms +≤ 36\/12 ms +ok/);
  assert.match(out, /morph close {3}15\/10 ms +≤ 36\/12 ms +ok/);
  assert.throws(
    () => execFileSync('node', [cli, ...args, '14', '9', '37', '10', '17', '8'], { stdio: 'pipe' }),
    (e) => e.status === 1 && /morph close {3}37\/10 ms +≤ 36\/12 ms +OVER/.test(e.stdout.toString()),
  );
  assert.throws(
    () => execFileSync('node', [cli, ...args], { stdio: 'pipe' }),
    (e) => e.status === 1 && /morph open {4}none/.test(e.stdout.toString()),
  );
});

test('frame intervals are the gaps between a morph\'s frames, the wait for its first frame left out', () => {
  assert.deepEqual(morphIntervals([[9, 176, 34], [17, 300, 80], [35, 600, 200], [43, 900, 400]]), [8, 18, 8]);
  assert.deepEqual(morphIntervals([[5, 176, 34]]), []);
});

// BH6GX53J and JN450PWP: the longest frame interval, and 95% of frames done within 12 ms; at 60 Hz an interval is 16.7 ms, so the 12 is each frame's own work.
test('the frames CLI prints a morph\'s longest interval and the p95 of its frames\' work from island state\'s frames', () => {
  const frames = JSON.stringify([[4, 0, 0, 0, 0, 3], [12, 0, 0, 0, 0, 2], [20, 0, 0, 0, 0, 9], [37, 0, 0, 0, 0, 4], [45, 0, 0, 0, 0, 1]]);
  assert.equal(execFileSync('node', [new URL('./bench.mjs', import.meta.url).pathname, 'frames', frames], { encoding: 'utf8' }).trim(), '17 9');
});

// The plan holds a switch from one surface to another to 20 ms at its longest and 12 ms at p95: the window's keyboard does not change, so no frame of its own lands in the morph.
test('a morph switch with a longest interval of 21 ms or a p95 of 13 ms is OVER, 20 and 12 ok', () => {
  assert.equal(report({ ...good, morphSwitch: { max: 20, p95: 12 } }, BUDGETS).over, false);
  const long = report({ ...good, morphSwitch: { max: 21, p95: 8 } }, BUDGETS);
  assert.equal(long.over, true);
  assert.equal(long.lines[23], 'morph switch  21/8 ms ≤ 20/12 ms OVER');
  assert.equal(report({ ...good, morphSwitch: { max: 14, p95: 13 } }, BUDGETS).over, true);
  assert.equal(report({ ...good, morphSwitch: null }, BUDGETS).lines[23], 'morph switch  none');
  assert.throws(
    () => execFileSync('node', [cli, ...args, '14', '9', '15', '10'], { stdio: 'pipe' }),
    (e) => e.status === 1 && /morph switch +none/.test(e.stdout.toString()),
  );
});
