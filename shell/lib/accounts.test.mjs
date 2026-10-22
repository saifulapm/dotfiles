import { test } from 'node:test';
import assert from 'node:assert/strict';
import { accountsView, accountsItems, accountsKeys } from './accounts.mjs';

process.env.TZ = 'Asia/Dhaka';

const NOW = Date.parse('2026-10-22T09:12:00Z');
const AS_OF = '2026-10-22T09:12:00Z';
const registry = JSON.stringify({
  active: 'main',
  accounts: [
    { id: 'main', label: 'main', home: '/h/.claude', email: 'a@b.c', plan: 'max' },
    { id: 'work', label: 'work', home: '/h/work', email: 'x@y.z', plan: 'pro' },
  ],
});
const row = (o) => Object.assign({ account: null, limit: null, unit: '%', resets_at: null, as_of: AS_OF, state: 'ok', reason: null }, o);
const claude = (account, metric, value, resets_at) => row({ provider: 'claude', label: account, account, metric, kind: 'percent', value, limit: 100, resets_at });
const rows = [
  claude('main', '5-hour', 34, '2026-10-22T11:00:00.504285+00:00'),
  claude('main', 'weekly', 61, '2026-10-29T03:00:00Z'),
  claude('main', 'weekly Fable', 22, '2026-10-29T03:00:00Z'),
  claude('work', '5-hour', 8, '2026-10-22T10:40:00Z'),
  claude('work', 'weekly', 12, null),
  row({ provider: 'deepseek-ai', label: 'DeepSeek', metric: 'balance', kind: 'money', value: 12.4, unit: 'USD' }),
  row({ provider: 'openrouter', label: 'OpenRouter', metric: 'balance', kind: 'money', value: 3.1, limit: 10, unit: 'USD' }),
  row({ provider: 'zenmux', label: 'ZenMux', metric: 'balance', kind: 'money', value: 7, unit: 'USD' }),
  row({ provider: 'vercel', label: 'Vercel AI', metric: 'balance', kind: 'money', value: 4.5, unit: 'USD' }),
  row({ provider: 'fal', label: 'fal', metric: 'balance', kind: 'money', value: 18.2, unit: 'USD' }),
  row({ provider: 'elevenlabs', label: 'ElevenLabs', metric: 'characters', kind: 'count', value: 11500, limit: 32000, unit: 'characters', resets_at: '2026-11-03T00:00:00Z' }),
  row({ provider: 'codex', label: 'Codex', metric: 'monthly', kind: 'percent', value: 0, limit: 100, resets_at: '2026-11-19T06:00:00Z' }),
];
const view = (r = rows, reg = registry, busy = false) => accountsView(reg, JSON.stringify(r), NOW, busy);

test('the recorded rows give two Claude accounts, five balances and two usage rows', () => {
  const v = view();
  assert.deepEqual(v.accounts.map((a) => [a.id, a.label, a.plan, a.active]), [['main', 'main', 'Max', true], ['work', 'work', 'Pro', false]]);
  assert.equal(v.balances.length, 5);
  assert.equal(v.usage.length, 2);
  assert.deepEqual(v.groups, [['Claude', 2], ['Balances', 5], ['Usage', 2]]);
});

test("main's limits read as the board draws them: percent used and the reset in local time", () => {
  const main = view().accounts[0];
  assert.deepEqual(
    main.limits.map((l) => [l.name, l.figure, l.reset]),
    [['5-hour', '34% used', 'resets 17:00'], ['Weekly', '61% used', 'resets Thu 09:00'], ['Weekly Fable', '22% used', 'resets Thu 09:00']],
  );
  assert.equal(main.limits[0].fraction, 0.34);
});

test('a limit at 80% or more warns, one at 79% does not, and the bar never leaves 0 to 1', () => {
  const r = [claude('main', '5-hour', 92, null), claude('main', 'weekly', 79, null), claude('main', 'weekly Fable', 80, null), claude('work', '5-hour', 140, null), claude('work', 'weekly', -3, null)];
  const v = view(r);
  assert.deepEqual(v.accounts[0].limits.map((l) => l.warning), [true, false, true]);
  assert.deepEqual(v.accounts[1].limits.map((l) => l.fraction), [1, 0]);
});

test('balances read in money, OpenRouter of its grant with a bar of credit left; usage reads used of its cap', () => {
  const v = view();
  assert.deepEqual(v.balances.map((b) => [b.label, b.figure]), [['DeepSeek', '$12.40'], ['OpenRouter', '$3.10 of $10'], ['ZenMux', '$7.00'], ['Vercel AI', '$4.50'], ['fal', '$18.20']]);
  assert.equal(v.balances[1].fraction, 0.31);
  assert.equal(v.balances[0].fraction, null);
  assert.deepEqual(v.usage.map((u) => [u.label, u.figure, u.reset]), [['ElevenLabs', '11,500 of 32,000 characters', 'resets 3 Nov'], ['Codex', '0% of monthly window', 'resets 19 Nov']]);
  assert.equal(v.usage[0].warning, false);
});

test('a usage count at 80% of its cap warns', () => {
  const r = [row({ provider: 'elevenlabs', label: 'ElevenLabs', metric: 'characters', kind: 'count', value: 26000, limit: 32000, unit: 'characters' })];
  assert.equal(view(r).usage[0].warning, true);
});

test("an expired account dims its rows under one line that says when and what to do", () => {
  const r = rows.map((x) => (x.account === 'main' ? Object.assign({}, x, { state: 'stale', reason: 'expired', as_of: '2026-10-22T07:40:00Z' }) : x));
  const main = view(r).accounts[0];
  assert.equal(main.note, 'stale · as of 13:40 · run cx in this account');
  assert.equal(main.dim, true);
  assert.equal(main.limits[0].figure, '34% used');
  assert.equal(view(r).accounts[1].dim, false);
});

test('a stale balance keeps its value with its time; a refused key reads in the error voice', () => {
  const r = rows.map((x) => (x.provider === 'openrouter' ? Object.assign({}, x, { state: 'stale', reason: 'timeout', as_of: '2026-10-22T08:58:00Z' }) : x.provider === 'fal' ? Object.assign({}, x, { value: null, state: 'auth', reason: 'forbidden' }) : x));
  const v = view(r);
  assert.deepEqual([v.balances[1].figure, v.balances[1].note, v.balances[1].error], ['$3.10 of $10', 'as of 14:58', false]);
  assert.deepEqual([v.balances[4].figure, v.balances[4].note, v.balances[4].error], ['', "key can't read billing", true]);
});

test('a body the collector could not read says so and the other rows still draw', () => {
  const r = rows.concat([row({ provider: 'tabitoken', label: 'tabitoken', metric: 'balance', kind: 'money', value: null, state: 'error', reason: 'shape' })]);
  const v = view(r);
  assert.equal(v.balances.length, 6);
  assert.deepEqual([v.balances[5].note, v.balances[5].error], ["can't read", true]);
});

test('a registry account whose home is missing says so, and its limits are none', () => {
  const r = rows.filter((x) => x.account !== 'work').concat([row({ provider: 'claude', label: 'work', account: 'work', metric: '5-hour', kind: 'percent', value: null, state: 'auth', reason: 'no-home' })]);
  const work = view(r).accounts[1];
  assert.equal(work.note, 'home missing');
  assert.deepEqual(work.limits, []);
});

test('no registry is one account, main, active; a broken one too', () => {
  for (const reg of ['', '{', '{"accounts": 3}']) {
    const v = view(rows, reg);
    assert.deepEqual(v.accounts.map((a) => [a.id, a.active]), [['main', true]]);
  }
});

test('a label or name from a file or a provider is one line without bidi marks or control characters', () => {
  const reg = JSON.stringify({ active: 'main', accounts: [{ id: 'main', label: 'ma\nin‮\u001b[31m', home: '/h', plan: 'max\tplus' }] });
  const r = [row({ provider: 'x', label: 'Evil\n‮co\u0007rp', metric: 'balance', kind: 'money', value: 1, unit: 'USD' })];
  const v = view(r, reg);
  assert.equal(v.accounts[0].label, 'ma in [31m');
  assert.equal(v.accounts[0].plan, 'Max plus');
  assert.equal(v.balances[0].label, 'Evil co rp');
  const long = view([row({ provider: 'x', label: 'y'.repeat(200), metric: 'balance', kind: 'money', value: 1, unit: 'USD' })]).balances[0].label;
  assert.ok(long.length <= 40 && long.endsWith('…'), long);
});

test('a currency other than USD reads after the amount', () => {
  const r = [row({ provider: 'deepseek-ai', label: 'DeepSeek', metric: 'balance', kind: 'money', value: 80, unit: 'CNY' })];
  assert.equal(view(r).balances[0].figure, '80.00 CNY');
});

test('the footer says when the last fetch answered, and refreshing while one runs', () => {
  assert.equal(view().footer, 'as of 15:12');
  assert.equal(view(rows, registry, true).footer, 'refreshing…');
  assert.equal(view([]).footer, '');
});

test('the cursor stops on account and provider rows, never on a limit or a group label', () => {
  const items = accountsItems(view());
  assert.deepEqual(
    items.filter((i) => i.stop).map((i) => i.kind + ':' + i.label),
    ['account:main', 'account:work', 'balance:DeepSeek', 'balance:OpenRouter', 'balance:ZenMux', 'balance:Vercel AI', 'balance:fal', 'usage:ElevenLabs', 'usage:Codex'],
  );
  assert.deepEqual(items.slice(0, 5).map((i) => i.kind), ['group', 'account', 'limit', 'limit', 'limit']);
  assert.equal(items.find((i) => i.kind === 'account' && i.label === 'work').account, 'work');
  assert.equal(items.find((i) => i.kind === 'balance').account, null);
});

test('the key strip is the board\'s', () => {
  const look = { keys: (pairs) => pairs };
  assert.deepEqual(accountsKeys(look), [['↵', 'make active'], ['r', 'refresh'], ['esc', '']]);
});
