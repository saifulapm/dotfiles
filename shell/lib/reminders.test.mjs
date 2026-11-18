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

test('a time past what a Date holds is too far ahead, and a year is still set', () => {
  for (const q of ['3000000000h tea', '99999999999999999999m tea']) {
    const r = parseReminder(q, now);
    assert.equal(r.due, undefined, q);
    assert.equal(r.error, `Cannot set ${q.split(' ')[0]}: it is too far ahead`, q);
    assert.deepEqual(reminderRows(q, now, [], false), [{ title: r.error, detail: '' }], q);
  }
  assert.equal(parseReminder('8760h renew', now).due, now + 8760 * 3600000);
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
  for (const file of ['{', '', '{"a":1}', '[1,"a",null,[],{"x":1}]', JSON.stringify([{ id: 'a', text: 'keep', due: 'abc', created: now }, good]), JSON.stringify([{ ...good, text: 5 }]), JSON.stringify([{ ...good, id: undefined }]), JSON.stringify([{ ...good, due: 1e300 }]), JSON.stringify([{ ...good, created: 1e300 }])]) {
    assert.equal(readReminders(file).broken, true, file);
  }
  assert.deepEqual(readReminders(JSON.stringify([good])), { list: [good], broken: false });
  assert.deepEqual(readReminders('[]\n'), { list: [], broken: false });
});

const S = await import('./reminders.mjs');
const tea = parseReminder('20m tea', now);

test('a reminder set in the store is a pending record with its fields stamped now', () => {
  const { store, error } = S.setReminder(S.emptyStore(), tea, now);
  assert.equal(error, '');
  assert.equal(store.version, 1);
  const [r] = store.reminders;
  assert.deepEqual({ ...r, id: 'x' }, { id: 'x', text: 'tea', due: at('2026-10-22T15:12:00+06:00'), created: now, ended: null, stamps: { text: now, due: now, ended: now } });
  assert.deepEqual(S.pendingList(store), [{ id: r.id, text: 'tea', due: at('2026-10-22T15:12:00+06:00'), created: now }]);
});

test('the store file reads back as written, and one of the wrong shape does not parse', () => {
  const { store } = S.setReminder(S.emptyStore(), tea, now);
  assert.deepEqual(S.parseStore(JSON.stringify(store)), store);
  const good = store.reminders[0];
  for (const file of ['{', '', '[]', '{"reminders":1}', JSON.stringify({ reminders: [1] }), JSON.stringify({ reminders: [{ ...good, id: 5 }] }), JSON.stringify({ reminders: [{ ...good, id: '' }] }), JSON.stringify({ reminders: [{ ...good, text: 5 }] }), JSON.stringify({ reminders: [{ ...good, due: 'abc' }] }), JSON.stringify({ reminders: [{ ...good, ended: 'gone' }] })]) {
    assert.equal(S.parseStore(file), null, file);
  }
});

test('a pulled record with no text or a due no Date holds is left out and counted, and the rest are kept', () => {
  const { store } = S.setReminder(S.emptyStore(), tea, now);
  const good = store.reminders[0];
  const pulled = S.parseStore(JSON.stringify({ version: 1, reminders: [good, { ...good, id: 'e', text: '' }, { ...good, id: 'm', text: '\u202E\u001b' }, { ...good, id: 'f', due: 1e300 }] }));
  const { store: kept, dropped } = S.usableOnly(pulled);
  assert.equal(dropped, 3);
  assert.deepEqual(kept.reminders.map((r) => r.id), [good.id]);
});

const setOn = (store, q, t, id) => {
  const r = S.setReminder(store, parseReminder(q, t), t);
  return { ...r.store, reminders: r.store.reminders.map((x) => (x.created === t && x.text === q.split(' ').slice(1).join(' ') ? { ...x, id } : x)) };
};

test('two stores that each set a reminder merge to both pending, in either order', () => {
  const a = setOn(S.emptyStore(), '20m tea', now, 'r-a');
  const b = setOn(S.emptyStore(), '1h coffee', now + 1000, 'r-b');
  const ab = S.mergeStores(a, b);
  assert.deepEqual(ab, S.mergeStores(b, a));
  assert.deepEqual(S.pendingList(ab).map((r) => r.text), ['tea', 'coffee']);
});

test('a reminder removed on one machine is removed in the merge, and leaves the pending list', () => {
  const a = setOn(S.emptyStore(), '20m tea', now, 'r-a');
  const removed = S.endReminder(a, 'r-a', 'removed', now + 5000);
  assert.deepEqual([removed.reminders[0].ended, removed.reminders[0].stamps.ended, removed.reminders[0].text], ['removed', now + 5000, 'tea']);
  const merged = S.mergeStores(a, removed);
  assert.equal(merged.reminders[0].ended, 'removed');
  assert.deepEqual(S.pendingList(merged), []);
});

test('a rung reminder stays rung against a pending copy stamped later, so no clock reopens it', () => {
  const a = setOn(S.emptyStore(), '20m tea', now, 'r-a');
  const rung = S.endReminder(a, 'r-a', 'rung', now + 1000);
  const later = { ...a, reminders: [{ ...a.reminders[0], stamps: { text: now, due: now, ended: now + 9e9 } }] };
  assert.equal(S.mergeStores(rung, later).reminders[0].ended, 'rung');
  assert.equal(S.mergeStores(later, rung).reminders[0].ended, 'rung');
  assert.equal(S.endReminder(rung, 'r-a', 'removed', now + 2000).reminders[0].ended, 'rung');
});

test('the old reminders.json moves in with its ids, text, due and created, and a reminder already rung stays rung', () => {
  const old = readReminders(JSON.stringify([{ id: 'mwlvjgei-bf1', text: 'renew', due: 1795046400000, created: 1763000000000 }])).list;
  const moved = S.migrateOld(S.emptyStore(), old);
  assert.deepEqual(moved.reminders, [{ id: 'mwlvjgei-bf1', text: 'renew', due: 1795046400000, created: 1763000000000, ended: null, stamps: { text: 1763000000000, due: 1763000000000, ended: 1763000000000 } }]);
  const rung = S.endReminder(moved, 'mwlvjgei-bf1', 'rung', now);
  assert.equal(S.migrateOld(rung, old).reminders[0].ended, 'rung');
  assert.deepEqual(S.pendingList(S.migrateOld(rung, old)), []);
});

test('with 50 pending a new one is refused, and a merge of 30 and 30 keeps all 60', () => {
  const many = (prefix, n) => ({ version: 1, reminders: Array.from({ length: n }, (_, i) => ({ id: `${prefix}${i}`, text: 't', due: now + (i + 1) * 60000, created: now, ended: null, stamps: { text: now, due: now, ended: now } })) });
  const fifty = many('f', 50);
  assert.deepEqual(S.setReminder(fifty, tea, now), { store: fifty, error: 'At most 50 reminders can wait' });
  const sixty = S.mergeStores(many('a', 30), many('b', 30));
  assert.equal(S.pendingList(sixty).length, 60);
  const refused = S.setReminder(sixty, tea, now);
  assert.equal(refused.error, 'At most 50 reminders can wait');
  assert.equal(S.pendingList(refused.store).length, 60);
});

test('a pending text from another machine lists as one clean line', () => {
  const s = { version: 1, reminders: [{ id: 'p', text: 'a\nb\u202Ec\u001b[31m', due: now + 60000, created: now, ended: null, stamps: { text: now, due: now, ended: now } }] };
  assert.equal(S.pendingList(s)[0].text, 'a bc [31m');
  assert.equal(reminderRows('', now, S.pendingList(s))[0].title, 'a bc [31m');
});
