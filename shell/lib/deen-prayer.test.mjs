import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as P from './deen-prayer.mjs';

const fixture = (name) => JSON.parse(readFileSync(new URL(`../../dev/deen/${name}.json`, import.meta.url), 'utf8'));
const day = fixture('prayer---date-2026-10-23');
const times = day.times;
const at = (h, m) => new Date(2026, 9, 23, h, m);

test('DOTS_DEEN_NOW is an ISO local time, and anything else is no time', () => {
  const t = P.parseNow('2026-10-23T14:32');
  assert.deepEqual([t.getFullYear(), t.getMonth(), t.getDate(), t.getHours(), t.getMinutes()], [2026, 9, 23, 14, 32]);
  assert.equal(P.parseNow(''), null);
  assert.equal(P.parseNow(undefined), null);
  assert.equal(P.parseNow('half past two'), null);
  assert.equal(P.parseNow('2026-13-40T25:99'), null);
});

test('next is the first prayer after the minute, counting the minutes left', () => {
  assert.deepEqual(P.next(times, at(14, 32)), { name: 'asr', time: '15:50', left: 78 });
  assert.deepEqual(P.next(times, at(3, 0)), { name: 'fajr', time: '04:43', left: 103 });
  assert.deepEqual(P.next(times, at(15, 50)), { name: 'maghrib', time: '17:26', left: 96 });
  assert.equal(P.next(times, at(19, 10)), null);
});

test('after Isha the wait is to the next morning\'s Fajr', () => {
  assert.equal(P.untilTomorrow('04:44', at(19, 10)), 574);
});

test('a countdown reads hours and padded minutes, or bare minutes under an hour', () => {
  assert.equal(P.countdown(78), '1 h 18 min');
  assert.equal(P.countdown(65), '1 h 05 min');
  assert.equal(P.countdown(60), '1 h 00 min');
  assert.equal(P.countdown(574), '9 h 34 min');
  assert.equal(P.countdown(45), '45 min');
  assert.equal(P.countdown(0), '0 min');
});

test('the five rows, dimmed once passed, with the next one tagged and Asr always Hanafi', () => {
  const rows = P.rows(times, at(14, 32), true);
  assert.deepEqual(
    rows.map((r) => [r.name, r.time, r.past, r.next, r.tag]),
    [
      ['Fajr', '04:43', true, false, ''],
      ['Dhuhr', '11:43', true, false, ''],
      ['Asr', '15:50', false, true, 'next · Hanafi'],
      ['Maghrib', '17:26', false, false, ''],
      ['Isha', '18:42', false, false, ''],
    ],
  );
  const late = P.rows(times, at(17, 0), true);
  assert.deepEqual([late[2].past, late[2].next, late[2].tag, late[3].next, late[3].tag], [true, false, 'Hanafi', true, 'next']);
  assert.ok(P.rows(times, at(19, 10), true).every((r) => r.past && !r.next));
});

test('another day has nothing dimmed or next, and only Asr keeps its tag', () => {
  const rows = P.rows(times, at(14, 32), false);
  assert.ok(rows.every((r) => !r.past && !r.next));
  assert.deepEqual(rows.map((r) => r.tag), ['', '', 'Hanafi', '', '']);
});

test('the date line gives the weekday, the date and sunrise; Blueprint writes it in capitals with an ISO date', () => {
  assert.equal(P.dateLine('2026-10-23', '05:59', false), 'Friday 23 October 2026 · sunrise 05:59');
  assert.equal(P.dateLine('2026-10-23', '05:59', true), 'FRIDAY 2026-10-23 · SUNRISE 05:59');
});

test('the method line says whether the month is cached', () => {
  assert.equal(P.methodLine('University of Islamic Sciences, Karachi', true), 'Method: University of Islamic Sciences, Karachi · aladhan, cached for the month');
  assert.equal(P.methodLine('Karachi', false), 'Method: Karachi · aladhan');
});

test('days are moved and counted by date, across a month end', () => {
  assert.equal(P.dayKey(at(14, 32)), '2026-10-23');
  assert.equal(P.shiftDay('2026-10-31', 1), '2026-11-01');
  assert.equal(P.shiftDay('2026-03-01', -1), '2026-02-28');
  assert.equal(P.dayDiff('2026-10-23', '2026-10-24'), 1);
  assert.equal(P.dayWord(1), 'Tomorrow');
  assert.equal(P.dayWord(-1), 'Yesterday');
  assert.equal(P.dayWord(3), 'in 3 days');
  assert.equal(P.dayWord(-2), '2 days ago');
});

test('the backend\'s answer is read, and an error or a short answer is none', () => {
  const p = P.parsePrayer(day);
  assert.deepEqual([p.city, p.date, p.times.asr, p.times.sunrise, p.method, p.cached], ['Dhaka', '2026-10-23', '15:50', '05:59', 'University of Islamic Sciences, Karachi', true]);
  assert.equal(P.parsePrayer(null), null);
  assert.equal(P.parsePrayer({ error: 'offline' }), null);
  assert.equal(P.parsePrayer({ city: 'Dhaka', times: { fajr: '04:43' } }), null);
});

test('a prayer is named by its key and the minute is drawn as HH:MM', () => {
  assert.equal(P.nameOf('maghrib'), 'Maghrib');
  assert.equal(P.clock(at(9, 5)), '09:05');
});

test('a city is one line without controls or overrides', () => {
  const p = P.parsePrayer(fixture('prayer---date-2026-10-21'));
  assert.equal(p.city, 'Forged city [31mred');
});
