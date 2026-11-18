import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as R from './reminders.mjs';
import { eventIcs } from './reminder-event.mjs';

const T = Date.UTC(2026, 10, 19, 4, 30, 0);
const MIN = 60000;
const reminder = (text, due = T + 10 * MIN, created = T) => ({ id: 'mi4x2-ab12cd', text, due, created });
// Unfolds per RFC 5545 3.1, then reads each property's value by name.
const props = (ics) =>
  ics
    .replace(/\r\n[ \t]/g, '')
    .split('\r\n')
    .filter(Boolean)
    .map((l) => [l.slice(0, l.indexOf(':')), l.slice(l.indexOf(':') + 1)]);
const prop = (ics, name) => props(ics).filter(([k]) => k === name).map(([, v]) => v);

test('a reminder is one VEVENT with its id as UID, its text as SUMMARY, and UTC times from its due and created', () => {
  const ics = eventIcs(reminder('tea'));
  assert.deepEqual(prop(ics, 'BEGIN'), ['VCALENDAR', 'VEVENT', 'VALARM']);
  assert.deepEqual(prop(ics, 'END'), ['VALARM', 'VEVENT', 'VCALENDAR']);
  assert.deepEqual(prop(ics, 'VERSION'), ['2.0']);
  assert.equal(prop(ics, 'PRODID').length, 1);
  assert.deepEqual(prop(ics, 'UID'), ['mi4x2-ab12cd']);
  assert.deepEqual(prop(ics, 'SUMMARY'), ['tea']);
  assert.deepEqual(prop(ics, 'DTSTAMP'), ['20261119T043000Z']);
  assert.deepEqual(prop(ics, 'DTSTART'), ['20261119T044000Z']);
  assert.deepEqual(prop(ics, 'DTEND'), ['20261119T044500Z']);
});

test('its alarm rings at the start with the text', () => {
  const ics = eventIcs(reminder('tea'));
  assert.deepEqual(prop(ics, 'TRIGGER'), ['PT0S']);
  assert.deepEqual(prop(ics, 'ACTION'), ['DISPLAY']);
  assert.deepEqual(prop(ics, 'DESCRIPTION'), ['tea']);
});

test('every line ends in CRLF and the same reminder gives the same bytes', () => {
  const ics = eventIcs(reminder('tea'));
  assert.ok(ics.endsWith('END:VCALENDAR\r\n'));
  assert.ok(!/[^\r]\n/.test(ics));
  assert.equal(eventIcs(reminder('tea')), ics);
});

test('a comma, a semicolon and a backslash are escaped, and a stored newline reaches the event as the launcher shows it', () => {
  assert.deepEqual(prop(eventIcs(reminder('buy eggs, milk; a\\b')), 'SUMMARY'), ['buy eggs\\, milk\\; a\\\\b']);
  const store = { version: 1, reminders: [Object.assign(reminder('call\nmum'), { ended: null, stamps: { text: T, due: T, ended: T } })] };
  const [shown] = R.pendingList(store);
  assert.deepEqual(prop(eventIcs(shown), 'SUMMARY'), [shown.text]);
  assert.ok(!shown.text.includes('\n'));
});

test('a long text folds at 75 octets without splitting a character, and unfolds to itself', () => {
  const text = 'চা খেতে হবে, '.repeat(12) + 'x'.repeat(100);
  const ics = eventIcs(reminder(text));
  for (const line of ics.split('\r\n')) assert.ok(Buffer.byteLength(line) <= 75, `${Buffer.byteLength(line)} octets: ${line}`);
  assert.ok(!ics.includes('�'));
  assert.deepEqual(prop(ics, 'SUMMARY'), [text.replace(/,/g, '\\,')]);
});

test('a due across a DST change keeps its instant in UTC', () => {
  const due = Date.UTC(2026, 2, 29, 1, 30);
  assert.deepEqual(prop(eventIcs(reminder('tea', due)), 'DTSTART'), ['20260329T013000Z']);
});
