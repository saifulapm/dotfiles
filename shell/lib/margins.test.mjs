import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pad2, dateText, clockText, msToNextMinute, marginState, screenTail } from './margins.mjs';

const AT = new Date(2026, 9, 18, 14, 32, 10, 500);

test('pads a workspace index to two digits', () => {
  assert.equal(pad2(1), '01');
  assert.equal(pad2(12), '12');
});

test('the date reads as weekday, day and month', () => {
  assert.equal(dateText(AT), 'Sun 18 Oct');
  assert.equal(dateText(new Date(2026, 10, 2)), 'Mon 2 Nov');
});

test('the clock reads 24 hour HH:MM', () => {
  assert.equal(clockText(AT), '14:32');
  assert.equal(clockText(new Date(2026, 9, 19, 0, 5)), '00:05');
});

test('the tick waits until the next minute boundary', () => {
  assert.equal(msToNextMinute(AT), 49500);
  assert.equal(msToNextMinute(new Date(2026, 9, 18, 23, 59, 0, 0)), 60000);
});

test('the margin state for a focused window', () => {
  const s = marginState({ idx: 1, app: 'foot', title: '~/Sites/github/dotfiles' }, AT);
  assert.equal(
    JSON.stringify(s),
    '{"left":{"workspace":"01","app":"foot","title":"~/Sites/github/dotfiles","text":"01 · foot — ~/Sites/github/dotfiles"},"right":{"date":"Sun 18 Oct","text":"Sun 18 Oct"}}',
  );
});

test('the margin state for an empty workspace is just its number', () => {
  const s = marginState({ idx: 2, app: null, title: null }, AT);
  assert.equal(s.left.text, '02');
  assert.equal(s.left.workspace, '02');
});

test('on screen the number is followed by a dash, the app and the title', () => {
  assert.equal(screenTail({ app: 'foot', title: '~/Sites' }), ' — foot · ~/Sites');
  assert.equal(screenTail({ app: null, title: null }), '');
});
