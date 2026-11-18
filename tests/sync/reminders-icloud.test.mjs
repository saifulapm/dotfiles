// The reminders unit's last step: each pending reminder as an event in the Dots reminders iCloud calendar, against a fake iCloud.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import * as R from '../../shell/lib/reminders.mjs';
import { icloudEntry, machine, processArgs, sync, world } from './lib.mjs';
import { icloud, report } from './icloud.mjs';

const MIN = 60000;

const storePath = (m) => join(m.data, 'reminders', m.id + '.json');
const read = (m) => R.parseStore(readFileSync(storePath(m), 'utf8'));
const write = (m, store) => {
  mkdirSync(dirname(storePath(m)), { recursive: true });
  writeFileSync(storePath(m), JSON.stringify(store));
};
const status = (m) => JSON.parse(readFileSync(m.status, 'utf8'));
// Sets a reminder due in the future as the CLI would, now being the real clock so the round sees it pending.
const add = (m, q) => {
  const now = Date.now();
  let s;
  try {
    s = read(m);
  } catch {
    s = R.emptyStore();
  }
  const out = R.setReminder(s, R.parseReminder(q, now), now).store;
  write(m, out);
  return out.reminders.find((r) => !s.reminders.some((x) => x.id === r.id));
};

async function round(m) {
  const r = await sync(m, ['--only', 'reminders']);
  assert.equal(r.code, 0, `dots sync on ${m.id} exited ${r.code}: ${r.stdout}${r.stderr}`);
  return r;
}

async function setup(names) {
  const fake = await icloud(names);
  const w = world();
  const a = machine(w, 'a');
  icloudEntry(a, fake);
  return { fake, w, a };
}

test('after a reminder is set and a round, Dots reminders holds one event with its id as UID, its text as SUMMARY and an alert at the start', async (t) => {
  const { fake, a } = await setup();
  t.after(fake.close);
  const tea = add(a, '10m tea');
  await round(a);
  const events = await report(fake, 'Dots reminders');
  assert.deepEqual(events.map((e) => [e.uid, e.summary, e.trigger]), [[tea.id, 'tea', 'PT0S']]);
  assert.deepEqual(await report(fake, 'Home'), []);
  assert.equal(status(a).reminders.ok, true);
});

test('a second round with nothing changed sends no PUT', async (t) => {
  const { fake, a } = await setup();
  t.after(fake.close);
  add(a, '10m tea');
  await round(a);
  const puts = fake.count('PUT');
  assert.equal(puts, 1);
  fake.log.length = 0;
  await round(a);
  assert.equal(fake.count('PUT'), 0);
});

test('a reminder that rang keeps its event after the next round', async (t) => {
  const { fake, a } = await setup();
  t.after(fake.close);
  const tea = add(a, '10m tea');
  await round(a);
  write(a, R.endReminder(read(a), tea.id, 'rung', Date.now()));
  await round(a);
  assert.deepEqual((await report(fake, 'Dots reminders')).map((e) => e.uid), [tea.id]);
});

test('two machines pushing the same reminder leave one event', async (t) => {
  const { fake, w, a } = await setup();
  t.after(fake.close);
  const b = machine(w, 'b');
  icloudEntry(b, fake);
  const tea = add(a, '10m tea');
  await round(a);
  await round(b);
  assert.equal(fake.count('PUT'), 2);
  assert.deepEqual((await report(fake, 'Dots reminders')).map((e) => e.uid), [tea.id]);
});

test('an edited text goes up again as the same event', async (t) => {
  const { fake, a } = await setup();
  t.after(fake.close);
  const tea = add(a, '10m tea');
  await round(a);
  const now = Date.now();
  write(a, { version: 1, reminders: read(a).reminders.map((r) => Object.assign({}, r, { text: 'green tea', stamps: Object.assign({}, r.stamps, { text: now }) })) });
  await round(a);
  assert.deepEqual((await report(fake, 'Dots reminders')).map((e) => [e.uid, e.summary]), [[tea.id, 'green tea']]);
});

test('a text with a comma, a semicolon and a backslash reaches the event as the launcher shows it', async (t) => {
  const { fake, a } = await setup();
  t.after(fake.close);
  add(a, '10m eggs, milk; a\\b');
  await round(a);
  assert.deepEqual((await report(fake, 'Dots reminders')).map((e) => e.summary), ['eggs\\, milk\\; a\\\\b']);
});

test('with no calendar named Dots reminders, the unit fails naming it and nothing is put', async (t) => {
  const { fake, a } = await setup(['Home']);
  t.after(fake.close);
  add(a, '10m tea');
  const r = await sync(a, ['--only', 'reminders']);
  assert.equal(r.code, 5);
  assert.equal(status(a).reminders.error, 'reminders: iCloud has no calendar named Dots reminders');
  assert.equal(fake.count('PUT'), 0);
});

test('with two calendars named Dots reminders, the unit fails saying so and nothing is put', async (t) => {
  const { fake, a } = await setup(['Dots reminders', 'Dots reminders']);
  t.after(fake.close);
  add(a, '10m tea');
  const r = await sync(a, ['--only', 'reminders']);
  assert.equal(r.code, 5);
  assert.equal(status(a).reminders.error, 'reminders: iCloud has 2 calendars named Dots reminders');
  assert.equal(fake.count('PUT'), 0);
});

test('a removed reminder has its event deleted, once', async (t) => {
  const { fake, a } = await setup();
  t.after(fake.close);
  const tea = add(a, '10m tea');
  const walk = add(a, '20m walk');
  await round(a);
  write(a, R.endReminder(read(a), tea.id, 'removed', Date.now()));
  await round(a);
  assert.deepEqual((await report(fake, 'Dots reminders')).map((e) => e.uid), [walk.id]);
  fake.log.length = 0;
  await round(a);
  assert.equal(fake.count('DELETE'), 0);
});

test('a DELETE answered 404 leaves the unit ok', async (t) => {
  const { fake, a } = await setup();
  t.after(fake.close);
  const tea = add(a, '10m tea');
  await round(a);
  fake.calendars.find((c) => c.name === 'Dots reminders').events.clear();
  write(a, R.endReminder(read(a), tea.id, 'removed', Date.now()));
  await round(a);
  assert.equal(fake.count('DELETE'), 1);
  assert.equal(status(a).reminders.ok, true);
});

test('with no iCloud entry in pass, a round exits 0 and sends nothing to iCloud', async (t) => {
  const fake = await icloud();
  t.after(fake.close);
  const a = machine(world(), 'a');
  a.env.DOTS_CALDAV_URL = fake.url;
  add(a, '10m tea');
  await round(a);
  assert.deepEqual(fake.log, []);
  assert.equal(status(a).reminders.ok, true);
});

test("iCloud answering 401 fails the unit with it, after this machine's reminders went up to Dropbox", async (t) => {
  const { fake, w, a } = await setup();
  t.after(fake.close);
  fake.status = 401;
  const tea = add(a, '10m tea');
  const r = await sync(a, ['--only', 'reminders']);
  assert.equal(r.code, 5);
  assert.match(status(a).reminders.error, /401/);
  assert.equal(status(a).reminders.ok, false);
  const remote = join(w.remote, 'dots-sync/reminders/a.json');
  assert.ok(existsSync(remote));
  assert.deepEqual(R.parseStore(readFileSync(remote, 'utf8')).reminders.map((x) => x.id), [tea.id]);
  fake.status = 0;
  await round(a);
  assert.equal(status(a).reminders.ok, true);
  assert.deepEqual((await report(fake, 'Dots reminders')).map((e) => e.uid), [tea.id]);
});

test("the password reaches neither sync.json, the round's output nor any process's argv", async (t) => {
  const { fake, a } = await setup();
  t.after(fake.close);
  fake.delay = 400;
  add(a, '10m tea');
  let done = false;
  const running = sync(a, ['--only', 'reminders']).finally(() => (done = true));
  const seen = [];
  while (!done) seen.push((await processArgs(a)).stdout);
  const r = await running;
  assert.equal(r.code, 0, r.stderr);
  assert.ok(fake.log.length >= 4 && seen.length >= 10, `${fake.log.length} requests, ${seen.length} ps reads`);
  assert.ok(seen.some((ps) => ps.includes('dots-sync-icloud')), 'ps caught the push running');
  const secret = 'app-pass-1';
  const b64 = Buffer.from('me@x.test:' + secret).toString('base64');
  for (const text of [readFileSync(a.status, 'utf8'), r.stdout, r.stderr, ...seen]) {
    assert.ok(!text.includes(secret) && !text.includes(b64));
  }
  fake.status = 401;
  add(a, '20m walk');
  const failed = await sync(a, ['--only', 'reminders']);
  for (const text of [readFileSync(a.status, 'utf8'), failed.stdout, failed.stderr]) assert.ok(!text.includes(secret) && !text.includes(b64));
});

test("a pulled record whose id or due no event can carry stays off iCloud, and the reminders beside it still go up", async (t) => {
  const { fake, w, a } = await setup();
  t.after(fake.close);
  const now = Date.now();
  const rec = (id, due, text = 'odd') => ({ id, text, due, created: now, ended: null, stamps: { text: now, due: now, ended: now } });
  const peer = join(w.remote, 'dots-sync/reminders/c.json');
  mkdirSync(dirname(peer), { recursive: true });
  const good = rec('mzz1-good01', now + 10 * MIN, 'tea');
  writeFileSync(peer, JSON.stringify({ version: 1, reminders: [rec('x\r\nBEGIN:VALARM\r\nTRIGGER:-PT1H', now + 10 * MIN), rec('a\ud800b', now + 10 * MIN), rec('far1', 1e15), rec('__proto__', now + 10 * MIN), good] }));
  await round(a);
  assert.deepEqual((await report(fake, 'Dots reminders')).map((e) => [e.uid, e.summary]).sort(), [['__proto__', 'odd'], [good.id, 'tea']]);
  assert.equal(fake.count('PUT'), 2);
  assert.equal(status(a).reminders.ok, true);
  fake.log.length = 0;
  await round(a);
  assert.equal(fake.count('PUT'), 0);
});
