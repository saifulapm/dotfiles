import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cityRows, convert } from './worldclock.mjs';

const zone = (id, city, offset) => ({ id, city, offset });
const before = { home: 'Asia/Dhaka', zones: [
  zone('Asia/Dhaka', 'Dhaka', 21600), zone('UTC', 'UTC', 0),
  zone('Europe/London', 'London', 3600), zone('America/New_York', 'New York', -14400)] };
const after = { home: 'Asia/Dhaka', zones: [
  zone('Asia/Dhaka', 'Dhaka', 21600), zone('UTC', 'UTC', 0),
  zone('Europe/London', 'London', 0), zone('America/New_York', 'New York', -14400)] };
const nyHome = { home: 'America/New_York', zones: [
  zone('America/New_York', 'New York', -14400), zone('Asia/Dhaka', 'Dhaka', 21600)] };
const india = { home: 'Asia/Kolkata', zones: [zone('Asia/Kolkata', 'Kolkata', 19800), zone('UTC', 'UTC', 0)] };
// 15:12 in Dhaka on Thursday 2026-10-22.
const now = Date.UTC(2026, 9, 22, 9, 12);

test('rows read home first, then UTC, London and New York with offsets from home', () => {
  assert.deepEqual(cityRows(now, before), [
    { city: 'Dhaka', time: '15:12', offset: '', day: '', home: true },
    { city: 'UTC', time: '09:12', offset: '−6h', day: '', home: false },
    { city: 'London', time: '10:12', offset: '−5h', day: '', home: false },
    { city: 'New York', time: '05:12', offset: '−10h', day: '', home: false },
  ]);
});

test('a zone still in yesterday says so, a zone already in tomorrow says so', () => {
  // 02:00 Friday in Dhaka: UTC, London and New York are still on Thursday.
  const late = Date.UTC(2026, 9, 22, 20, 0);
  assert.deepEqual(cityRows(late, before).map((r) => [r.city, r.time, r.day]), [
    ['Dhaka', '02:00', ''], ['UTC', '20:00', 'yesterday'],
    ['London', '21:00', 'yesterday'], ['New York', '16:00', 'yesterday']]);
  assert.deepEqual(cityRows(Date.UTC(2026, 9, 22, 22, 0), nyHome).map((r) => [r.city, r.time, r.day, r.offset]), [
    ['New York', '18:00', '', ''], ['Dhaka', '04:00', 'tomorrow', '+10h']]);
});

test('London drops to +0 after the clocks go back and its row follows', () => {
  assert.equal(cityRows(now, after)[2].time, '09:12');
  assert.equal(cityRows(now, after)[2].offset, '−6h');
});

test('a half-hour zone keeps its minutes', () => {
  assert.deepEqual(cityRows(now, india).map((r) => [r.time, r.offset]), [['14:42', ''], ['09:12', '−5:30h']]);
});

test('17:00 nyc is 03:00 tomorrow at home', () => {
  assert.deepEqual(convert('17:00 nyc', now, before), {
    from: '17:00 New York', to: '03:00 Dhaka', day: 'tomorrow',
    text: '17:00 New York = 03:00 Dhaka · tomorrow', time: '03:00', utc: 'New York UTC−4 · Dhaka UTC+6' });
});

test('09:00 london follows the London offset in force', () => {
  assert.equal(convert('09:00 london', now, before).text, '09:00 London = 14:00 Dhaka');
  assert.equal(convert('09:00 london', now, after).text, '09:00 London = 15:00 Dhaka');
  assert.equal(convert('09:00 london', now, after).day, '');
});

test('a result on the other side of midnight carries the day word', () => {
  assert.equal(convert('20:00 utc', now, before).day, 'tomorrow');
  assert.deepEqual(convert('01:00 dhaka', now, nyHome), {
    from: '01:00 Dhaka', to: '15:00 New York', day: 'yesterday',
    text: '01:00 Dhaka = 15:00 New York · yesterday', time: '15:00', utc: 'Dhaka UTC+6 · New York UTC−4' });
});

test('aliases and city names are case-insensitive, and a half-hour home converts', () => {
  assert.equal(convert('17:00 NYC', now, before).from, '17:00 New York');
  assert.equal(convert('17:00 new york', now, before).from, '17:00 New York');
  assert.equal(convert(' 5:30 UTC ', now, before).text, '05:30 UTC = 11:30 Dhaka');
  assert.equal(convert('17:00 utc', now, india).text, '17:00 UTC = 22:30 Kolkata');
});

test('text it does not understand is null', () => {
  assert.equal(convert('2 + 2', now, before), null);
  assert.equal(convert('25:00 nyc', now, before), null);
  assert.equal(convert('17:60 nyc', now, before), null);
  assert.equal(convert('17:00 mars', now, before), null);
  assert.equal(convert('', now, before), null);
});

test('a conversion also gives the home time alone and both UTC offsets', () => {
  const c = convert('17:00 nyc', now, before);
  assert.deepEqual([c.time, c.utc], ['03:00', 'New York UTC−4 · Dhaka UTC+6']);
  assert.equal(convert('08:00 utc', now, before).utc, 'UTC · Dhaka UTC+6');
  assert.equal(convert('09:00 utc', now, india).utc, 'UTC · Kolkata UTC+5:30');
});
