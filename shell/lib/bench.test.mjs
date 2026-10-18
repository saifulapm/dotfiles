import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { report, BUDGETS } from './bench.mjs';

const cli = new URL('./bench.mjs', import.meta.url).pathname;
const good = { firstFrameMs: 130, rssKiB: 152576, coldMs: 48, warmMs: 4, timers: 1, cpu: '0.03' };

test('every measure within budget reads ok and passes', () => {
  const r = report(good, BUDGETS);
  assert.equal(r.over, false);
  assert.deepEqual(r.lines, [
    'first frame   130 ms  ≤ 150 ms   ok',
    'idle rss      149 MiB ≤ 150 MiB  ok',
    'panel cold    48 ms   ≤ 50 ms    ok',
    'panel warm    4 ms    ≤ 16 ms    ok',
    'timers        1       = 1        ok',
    'idle cpu      0.03 %',
  ]);
});

test('one measure over its budget reads OVER and fails', () => {
  const r = report({ ...good, warmMs: 17 }, BUDGETS);
  assert.equal(r.over, true);
  assert.equal(r.lines[3], 'panel warm    17 ms   ≤ 16 ms    OVER');
});

test('RSS a KiB over the budget is OVER, not rounded down into it', () => {
  assert.equal(report({ ...good, rssKiB: 150 * 1024 + 1 }, BUDGETS).over, true);
});

test('a timer count other than the budget is OVER either way', () => {
  assert.equal(report({ ...good, timers: 0 }, BUDGETS).over, true);
  assert.equal(report({ ...good, timers: 2 }, BUDGETS).over, true);
});

test('the CLI exits 1 when an env budget is exceeded and 0 otherwise', () => {
  const args = ['130', '152576', '48', '4', '1', '0.03'];
  assert.match(execFileSync('node', [cli, ...args], { encoding: 'utf8' }), /panel warm {4}4 ms/);
  assert.throws(
    () => execFileSync('node', [cli, ...args], { env: { ...process.env, DOTS_BUDGET_FIRST_FRAME_MS: '1' }, stdio: 'pipe' }),
    (e) => e.status === 1 && /first frame +130 ms +≤ 1 ms +OVER/.test(e.stdout.toString()),
  );
});
