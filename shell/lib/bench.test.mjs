import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { report, switchCycle, BUDGETS } from './bench.mjs';

const cli = new URL('./bench.mjs', import.meta.url).pathname;
const good = { firstFrameMs: 130, rssKiB: 152576, coldMs: 48, warmMs: 4, timers: 1, switchMs: 120, switchedKiB: 157000, cpu: '0.03' };

test('every measure within budget reads ok and passes', () => {
  const r = report(good, BUDGETS);
  assert.equal(r.over, false);
  assert.deepEqual(r.lines, [
    'first frame   130 ms  ≤ 150 ms   ok',
    'idle rss      149 MiB ≤ 180 MiB  ok',
    'panel cold    48 ms   ≤ 50 ms    ok',
    'panel warm    4 ms    ≤ 16 ms    ok',
    'timers        1       = 1        ok',
    'theme switch  120 ms  ≤ 300 ms   ok',
    'idle cpu      0.03 %  ≤ 0.07 %   ok',
    'rss switched  153 MiB',
  ]);
});

test('one measure over its budget reads OVER and fails', () => {
  const r = report({ ...good, warmMs: 17 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[3], 'panel warm    17 ms   ≤ 16 ms    OVER');
});

test('a first frame of 150 ms passes and 160 ms is OVER', () => {
  assert.equal(report({ ...good, firstFrameMs: 150 }, BUDGETS).over, false);
  assert.equal(report({ ...good, firstFrameMs: 160 }, BUDGETS).over, true);
});

test('RSS a KiB over the 180 MiB budget is OVER, not rounded down into it', () => {
  assert.equal(report({ ...good, rssKiB: 180 * 1024 }, BUDGETS).over, false);
  assert.equal(report({ ...good, rssKiB: 180 * 1024 + 1 }, BUDGETS).over, true);
});

test('a timer count other than the budget is OVER either way', () => {
  assert.equal(report({ ...good, timers: 0 }, BUDGETS).over, true);
  assert.equal(report({ ...good, timers: 2 }, BUDGETS).over, true);
});

test('the CLI exits 1 when an env budget is exceeded and 0 otherwise', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03', '120', '157000'];
  assert.match(execFileSync('node', [cli, ...args], { encoding: 'utf8' }), /panel warm {4}4 ms/);
  assert.throws(
    () => execFileSync('node', [cli, ...args], { env: { ...process.env, DOTS_BUDGET_FIRST_FRAME_MS: '1' }, stdio: 'pipe' }),
    (e) => e.status === 1 && /first frame +130 ms +≤ 1 ms +OVER/.test(e.stdout.toString()),
  );
});

test('the slowest of the six theme switches over 300 ms is OVER', () => {
  const r = report({ ...good, switchMs: 301 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[5], 'theme switch  301 ms  ≤ 300 ms   OVER');
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
  assert.equal(r.lines[6], 'idle cpu      0.08 %  ≤ 0.07 %   OVER');
});
