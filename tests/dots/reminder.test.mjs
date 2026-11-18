// bin/reminder on a scratch data dir, at 10:00:00 UTC on a set day: what an agent runs to set, list and cancel a reminder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import * as R from '../../shell/lib/reminders.mjs';

const bin = new URL('../../bin/reminder', import.meta.url).pathname;
const fixedNow = new URL('fixed-now.mjs', import.meta.url).pathname;
const MIN = 60000;
// The fixtures here and the CLI read one clock.
process.env.TZ = 'UTC';
const T = Date.UTC(2026, 10, 19, 10, 0, 0);

function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'reminder-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const path = join(root, 'data', 'dots', 'reminders', 'a.json');
  const env = { ...process.env, TZ: 'UTC', DOTS_MACHINE: 'a', XDG_DATA_HOME: join(root, 'data'), NODE_OPTIONS: `--import=${fixedNow}`, FIXED_NOW: String(T) };
  const run = (...args) => spawnSync(bin, args, { env, encoding: 'utf8' });
  const read = () => (existsSync(path) ? readFileSync(path, 'utf8') : null);
  const write = (store) => {
    mkdirSync(join(path, '..'), { recursive: true });
    writeFileSync(path, JSON.stringify(store));
  };
  return { run, read, write, store: () => R.parseStore(read()) };
}

test('reminder add 20m tea prints the text, how long and the clock, and the store holds it pending', (t) => {
  const s = scratch(t);
  const r = s.run('add', '20m', 'tea');
  assert.equal(r.stdout, 'tea · in 20m · 10:20\n', r.stderr);
  assert.equal(r.status, 0);
  assert.deepEqual(
    R.pendingList(s.store()).map((x) => [x.text, x.due]),
    [['tea', T + 20 * MIN]],
  );
});

test('reminder add takes the text from every word after the time', (t) => {
  const s = scratch(t);
  assert.equal(s.run('add', '1h30m', 'call', 'Rubel').stdout, 'call Rubel · in 1h 30m · 11:30\n');
  assert.equal(s.run('add', '17:30', 'stretch now').stdout, 'stretch now · in 7h 30m · 17:30\n');
  assert.deepEqual(R.pendingList(s.store()).map((x) => x.text), ['call Rubel', 'stretch now']);
});

test('reminder add refuses a time not in the future, or no clock shows, in the launcher\'s words, and leaves the store', (t) => {
  const s = scratch(t);
  s.write(R.setReminder(R.emptyStore(), R.parseReminder('5m tea', T - MIN), T - MIN).store);
  const before = s.read();
  for (const [when, said] of [['0m', 'Cannot set 0m: it is not in the future'], ['25:00', 'Cannot set 25:00: no clock shows it']]) {
    const r = s.run('add', when, 'tea');
    assert.equal(r.stderr, said + '\n');
    assert.equal(r.stdout, '');
    assert.equal(r.status, 1);
  }
  assert.equal(s.read(), before);
});

test('reminder add with no text, or a time it cannot read, exits 1 and sets nothing', (t) => {
  const s = scratch(t);
  for (const args of [['20m', ''], ['20m', '  '], ['20m'], ['soon', 'tea']]) {
    const r = s.run('add', ...args);
    assert.equal(r.status, 1, args.join(' '));
    assert.notEqual(r.stderr, '');
  }
  assert.equal(s.read(), null);
});

test('reminder add refuses a 51st pending reminder', (t) => {
  const s = scratch(t);
  let store = R.emptyStore();
  for (let i = 1; i <= 50; i++) store = R.setReminder(store, R.parseReminder(`${i}m r${i}`, T), T).store;
  s.write(store);
  const before = s.read();
  const r = s.run('add', '5m', 'tea');
  assert.equal(r.stderr, 'At most 50 reminders can wait\n');
  assert.equal(r.status, 1);
  assert.equal(s.read(), before);
});

// An agent may pass anything it was given; the launcher shows such a text as one clean line, and so does the store.
test('reminder add stores and prints a text holding a newline, a bidi override and an escape code as one clean line', (t) => {
  const s = scratch(t);
  const r = s.run('add', '20m', 'a\nb\u202Ec\x1b[31m');
  assert.equal(r.stdout, 'a bc [31m · in 20m · 10:20\n');
  assert.deepEqual(s.store().reminders.map((x) => x.text), ['a bc [31m']);
});

// Nothing in the CLI needs the shell; the shell reads the store at its start and rings what is due, as it does any store.
test('reminder add with no shell running leaves a store the shell reads, the reminder pending', (t) => {
  const s = scratch(t);
  s.run('add', '20m', 'tea');
  const [r] = s.store().reminders;
  assert.equal(r.ended, null);
  assert.equal(r.created, T);
});

test('reminder add on a store that does not parse says so and leaves it', (t) => {
  const s = scratch(t);
  s.write({ version: 1, reminders: [{ id: 1 }] });
  const before = s.read();
  const r = s.run('add', '20m', 'tea');
  assert.equal(r.stderr, R.brokenStore('a') + '\n');
  assert.equal(r.status, 1);
  assert.equal(s.read(), before);
});

const storeOf = (...qs) => qs.reduce((s, q) => R.setReminder(s, R.parseReminder(q, T), T).store, R.emptyStore());

test('reminder list prints each pending reminder soonest first, with its id, when it rings and its text', (t) => {
  const s = scratch(t);
  // Set out of order, and one already rung, which is not listed.
  const store = storeOf('10:00 call', '17:30 tea', '5m gone');
  s.write(R.endReminder(store, store.reminders[2].id, 'rung', T));
  const r = s.run('list');
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.split('\n').filter(Boolean);
  assert.equal(lines.length, 2);
  const [tea, call] = [store.reminders[1], store.reminders[0]];
  assert.match(lines[0], new RegExp(`^${tea.id}\\s+17:30\\s+tea$`));
  assert.match(lines[1], new RegExp(`^${call.id}\\s+tomorrow 10:00\\s+call$`));
});

test('reminder list --json prints the pending records for an agent', (t) => {
  const s = scratch(t);
  const store = storeOf('10:00 call', '17:30 tea');
  s.write(store);
  const got = JSON.parse(s.run('list', '--json').stdout);
  assert.deepEqual(got.map((x) => [x.id, x.text, x.due]), [[store.reminders[1].id, 'tea', T + 450 * MIN], [store.reminders[0].id, 'call', T + 1440 * MIN]]);
});

test('reminder list with nothing pending says so and exits 0, and --json prints an empty array', (t) => {
  const s = scratch(t);
  assert.equal(s.run('list').stdout, 'no reminders\n');
  assert.equal(s.run('list').status, 0);
  assert.equal(s.run('list', '--json').stdout, '[]\n');
});

// Another machine's file may hold a text no CLI or launcher cleaned.
test('reminder list prints a stored text holding a newline and an escape code as one clean line', (t) => {
  const s = scratch(t);
  const store = storeOf('20m tea');
  store.reminders[0].text = 'a\nb\x1b[31m';
  s.write(store);
  assert.match(s.run('list').stdout, /\s10:20\s+a b \[31m\n$/);
  assert.equal(JSON.parse(s.run('list', '--json').stdout)[0].text, 'a b [31m');
});
