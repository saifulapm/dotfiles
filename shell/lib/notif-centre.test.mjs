import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ageText, badgeText, centreRows, countText, firstNote } from './notif-centre.mjs';

const note = (key, app, summary, time) => ({ key, app, summary, body: '', time });

test('the rows are each app under its head, newest app first, each newest first', () => {
  const history = [note(3, 'Mail', 'Two', 30), note(2, 'Chat', 'Hi', 20), note(1, 'Mail', 'One', 10)];
  const rows = centreRows(history, '', {}, '');
  assert.deepEqual(
    rows.map((r) => (r.kind === 'head' ? `head ${r.app}` : `note ${r.entry.summary}`)),
    ['head Mail', 'note Two', 'note One', 'head Chat', 'note Hi'],
  );
  assert.equal(rows[0].letter, 'M');
  assert.equal(rows[0].first, true);
  assert.equal(rows[3].first, false);
});

test('a search keeps only the matching notes and the heads over them', () => {
  const history = [note(3, 'Mail', 'Two', 30), note(2, 'Chat', 'Hi', 20), note(1, 'Mail', 'One', 10)];
  const rows = centreRows(history, 'two', {}, '');
  assert.deepEqual(rows.map((r) => r.kind + ' ' + (r.kind === 'head' ? r.app : r.entry.summary)), ['head Mail', 'note Two']);
});

test('an app whose rules are open has its three rule rows under its head, before its notes', () => {
  const rows = centreRows([note(1, 'Mail', 'One', 10)], '', { Mail: { muted: true } }, 'Mail');
  assert.deepEqual(rows.map((r) => r.kind + ' ' + (r.field ?? '')), ['head ', 'rule muted', 'rule dnd', 'rule stays', 'note ']);
  assert.equal(rows[0].badge, 'Muted');
  assert.equal(rows[2].greyed, true, 'Show during Do Not Disturb greys while muted');
  assert.equal(rows[1].greyed, false);
});

test('the badge reads the rule as board 5 names it, and an app with none has no badge', () => {
  assert.equal(badgeText(undefined), '');
  assert.equal(badgeText({ muted: true }), 'Muted');
  assert.equal(badgeText({ stays: 3000 }), '3 s');
  assert.equal(badgeText({ dnd: true, stays: 10000 }), 'Through DND · 10 s');
  assert.equal(badgeText({ stays: 0 }), 'Until dismissed');
  // Muted, nothing shows, so letting it through Do Not Disturb says nothing.
  assert.equal(badgeText({ muted: true, dnd: true, stays: 3000 }), 'Muted · 3 s');
});

test('an app name is one clean line, and its circle takes its first letter', () => {
  const rows = centreRows([note(1, '‮mail\u001b\nx', 'One', 10)], '', {}, '');
  assert.equal(rows[0].name, 'mail x');
  assert.equal(rows[0].letter, 'M');
  assert.equal(centreRows([note(1, '', 'One', 10)], '', {}, '')[0].letter, '•');
});

test('the count is every notification, or how many a search leaves of them', () => {
  assert.equal(countText(4, 4, ''), '4');
  assert.equal(countText(1, 4, 'inv'), '1 of 4');
  assert.equal(countText(0, 0, ''), '');
});

test('the centre opens on the first note, past its head', () => {
  const rows = centreRows([note(1, 'Mail', 'One', 10)], '', {}, '');
  assert.equal(firstNote(rows), 1);
  assert.equal(firstNote([]), 0);
});

test('an age reads as board 5 writes it', () => {
  assert.equal(ageText(20_000), 'now');
  assert.equal(ageText(2 * 60_000 + 5), '2 min');
  assert.equal(ageText(3 * 3_600_000), '3 h');
  assert.equal(ageText(2 * 86_400_000), '2 d');
});
