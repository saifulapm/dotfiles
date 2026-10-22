import { test } from 'node:test';
import assert from 'node:assert/strict';

// Reminders read and write the local clock, so every test runs at home.
process.env.TZ = 'Asia/Dhaka';
const { parseReminder, whenText, addReminder, dueReminders, firedText, reminderRows, readReminders, MAX_PENDING, BROKEN } = await import('./reminders.mjs');

const at = (s) => new Date(s).getTime();
const now = at('2026-10-22T14:52:00+06:00');

test('r 20m stand up previews the text, in 20m and the clock time it rings', () => {
  const r = parseReminder('20m stand up', now);
  assert.deepEqual([r.text, r.due, r.when], ['stand up', at('2026-10-22T15:12:00+06:00'), 'in 20m · 15:12']);
});

test('hours and hours with minutes count from now', () => {
  assert.equal(parseReminder('1h tea', now).due, at('2026-10-22T15:52:00+06:00'));
  assert.equal(parseReminder('1h30m tea', now).when, 'in 1h 30m · 16:22');
});

test('a clock time later today rings today, and one already past rings tomorrow', () => {
  assert.deepEqual([parseReminder('17:30 call Rubel', now).due, parseReminder('17:30 call Rubel', now).when], [at('2026-10-22T17:30:00+06:00'), 'in 2h 38m · 17:30']);
  const evening = at('2026-10-22T18:00:00+06:00');
  assert.deepEqual([parseReminder('17:30 call', evening).due, parseReminder('17:30 call', evening).when], [at('2026-10-23T17:30:00+06:00'), 'tomorrow 17:30']);
});

test('0m, 25:00 and 9:60 cannot be set, and the row says so', () => {
  for (const q of ['0m x', '0h x', '25:00 x', '9:60 x']) {
    const r = parseReminder(q, now);
    assert.equal(r.due, undefined, q);
    assert.match(r.error, /^Cannot set /, q);
  }
});

test('a query with no time or no text yet previews nothing', () => {
  for (const q of ['', '20m', '20m ', 'tea', 'soon tea']) assert.equal(parseReminder(q, now), null, q);
});

test("a reminder's text is one line with no control or bidi characters", () => {
  assert.equal(parseReminder('5m a\nb\u202Ec\u001b[31md\u0085e', now).text, 'a bc [31md e');
});

test('a pending row says the clock time today, tomorrow and a weekday after', () => {
  assert.equal(whenText(at('2026-10-22T17:30:00+06:00'), now), '17:30');
  assert.equal(whenText(at('2026-10-23T10:00:00+06:00'), now), 'tomorrow 10:00');
  assert.equal(whenText(at('2026-10-24T10:00:00+06:00'), now), 'Sat 10:00');
});

test('a new reminder is stored with an id, text, due and created, soonest first, and the 51st is refused', () => {
  const a = addReminder([], parseReminder('2h later', now), now);
  const b = addReminder(a.list, parseReminder('5m sooner', now), now);
  assert.deepEqual(b.list.map((r) => r.text), ['sooner', 'later']);
  assert.deepEqual(Object.keys(b.list[0]).sort(), ['created', 'due', 'id', 'text']);
  assert.notEqual(b.list[0].id, b.list[1].id);
  assert.equal(b.list[0].created, now);
  let list = [];
  for (let i = 0; i < MAX_PENDING; i++) list = addReminder(list, parseReminder(`${i + 1}m r${i}`, now), now).list;
  const full = addReminder(list, parseReminder('5m one more', now), now);
  assert.equal(full.list.length, 50);
  assert.match(full.error, /50/);
});

test('due reminders are the ones at or before now, the rest stay pending', () => {
  const list = [{ id: 'a', text: 'x', due: now - 60000, created: now - 120000 }, { id: 'b', text: 'y', due: now, created: now - 60000 }, { id: 'c', text: 'z', due: now + 1, created: now }];
  const { fire, keep } = dueReminders(list, now);
  assert.deepEqual([fire.map((r) => r.id), keep.map((r) => r.id)], [['a', 'b'], ['c']]);
});

test('a rung reminder reads Reminder · its text, and says when it was set', () => {
  const r = { id: 'a', text: 'tea', due: now, created: at('2026-10-22T14:51:00+06:00') };
  assert.deepEqual(firedText(r, now), { summary: 'Reminder · tea', body: 'set at 14:51' });
  assert.equal(firedText({ ...r, created: at('2026-10-21T09:05:00+06:00') }, now).body, 'set yesterday at 09:05');
});

const pending = [
  { id: 'b', text: 'Call Rubel', due: at('2026-10-22T17:30:00+06:00'), created: now },
  { id: 'c', text: 'Push lareys release', due: at('2026-10-23T10:00:00+06:00'), created: now },
];

test('the r rows are the preview, then each pending reminder soonest first under its head', () => {
  const rows = reminderRows('20m stand up', now, pending);
  assert.deepEqual(rows.map((r) => [r.title, r.detail]), [['stand up', 'in 20m · 15:12'], ['Call Rubel', '17:30'], ['Push lareys release', 'tomorrow 10:00']]);
  assert.deepEqual(rows[0].remind, { text: 'stand up', due: at('2026-10-22T15:12:00+06:00') });
  assert.deepEqual(rows.map((r) => [r.reminderId ?? null, !!r.head]), [[null, false], ['b', true], ['c', false]]);
});

test('with no time typed yet the r rows are the pending ones, and a time no clock has is a row that sets nothing', () => {
  assert.deepEqual(reminderRows('', now, pending).map((r) => r.reminderId), ['b', 'c']);
  const bad = reminderRows('25:00 x', now, pending)[0];
  assert.match(bad.title, /^Cannot set 25:00/);
  assert.equal(bad.remind, undefined);
});

test('with 50 waiting the preview row says no more can be set', () => {
  const full = Array.from({ length: 50 }, (_, i) => ({ id: `r${i}`, text: 't', due: now + (i + 1) * 60000, created: now }));
  const top = reminderRows('5m one more', now, full)[0];
  assert.match(top.title, /50/);
  assert.equal(top.remind, undefined);
});

test('while reminders.json does not parse, the preview row says so and sets nothing', () => {
  const top = reminderRows('5m tea', now, pending, true)[0];
  assert.equal(top.title, BROKEN);
  assert.match(BROKEN, /reminders\.json does not parse/);
  assert.equal(top.remind, undefined);
  assert.equal(reminderRows('', now, pending, true).length, 2);
});

test('reminders.json is read as the list, each text one line with no control or bidi characters', () => {
  const file = JSON.stringify([{ id: 'a', text: 'a\nb\u202Ec\u001b[31md\u0085e', due: now + 60000, created: now }]);
  const { list, broken } = readReminders(file);
  assert.equal(broken, false);
  assert.deepEqual(list, [{ id: 'a', text: 'a bc [31md e', due: now + 60000, created: now }]);
  assert.equal(firedText(list[0], now).summary, 'Reminder · a bc [31md e');
  assert.equal(reminderRows('', now, list)[0].title, 'a bc [31md e');
});

test('a reminders.json holding anything but reminders is broken, so nothing is set over it', () => {
  const good = { id: 'b', text: 'valid', due: now + 60000, created: now };
  for (const file of ['{', '', '{"a":1}', '[1,"a",null,[],{"x":1}]', JSON.stringify([{ id: 'a', text: 'keep', due: 'abc', created: now }, good]), JSON.stringify([{ ...good, text: 5 }]), JSON.stringify([{ ...good, id: undefined }])]) {
    assert.equal(readReminders(file).broken, true, file);
  }
  assert.deepEqual(readReminders(JSON.stringify([good])), { list: [good], broken: false });
  assert.deepEqual(readReminders('[]\n'), { list: [], broken: false });
});
