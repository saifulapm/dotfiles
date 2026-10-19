import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pad2, dateText, clockText, msToNextMinute, marginState, screenTail, batteryText, wifiText } from './margins.mjs';

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
  const s = marginState({ idx: 1, app: 'foot', title: '~/Sites/github/dotfiles' }, AT, { goal: '', wifi: 'wifi', battery: '82%' });
  assert.equal(
    JSON.stringify(s),
    '{"left":{"workspace":"01","app":"foot","title":"~/Sites/github/dotfiles","text":"01 · foot — ~/Sites/github/dotfiles"},"right":{"goal":"","wifi":"wifi","battery":"82%","date":"Sun 18 Oct","text":"wifi  82%  Sun 18 Oct"}}',
  );
});

test('the margin state for an empty workspace is just its number', () => {
  const s = marginState({ idx: 2, app: null, title: null }, AT, { goal: '', wifi: '', battery: '' });
  assert.equal(s.left.text, '02');
  assert.equal(s.left.workspace, '02');
});

test('on screen the number is followed by a dash, the app and the title', () => {
  assert.equal(screenTail({ app: 'foot', title: '~/Sites' }), ' — foot · ~/Sites');
  assert.equal(screenTail({ app: null, title: null }), '');
});

test('the battery reads its percentage, and says when it is charging', () => {
  assert.equal(batteryText(0.82, false), '82%');
  assert.equal(batteryText(0.82, true), '82% charging');
});

test('the top-right drops the parts that are absent', () => {
  const view = { idx: 1, app: null, title: null };
  assert.equal(marginState(view, AT, { goal: '', wifi: 'no wifi', battery: '' }).right.text, 'no wifi  Sun 18 Oct');
  assert.equal(marginState(view, AT, { goal: '', wifi: '', battery: '82% charging' }).right.text, '82% charging  Sun 18 Oct');
  assert.equal(marginState(view, AT, { goal: '', wifi: '', battery: '' }).right.text, 'Sun 18 Oct');
});

test('the active goal opens the top-right, and an empty one leaves no gap', () => {
  const view = { idx: 1, app: null, title: null };
  const s = marginState(view, AT, { goal: 'Ship v2 · 3d', wifi: 'wifi', battery: '82%' });
  assert.equal(s.right.goal, 'Ship v2 · 3d');
  assert.equal(s.right.text, 'Ship v2 · 3d  wifi  82%  Sun 18 Oct');
  assert.equal(marginState(view, AT, { goal: '', wifi: 'wifi', battery: '82%' }).right.text.startsWith('wifi'), true);
});

test('a failing sync opens the top-right, before the goal', () => {
  const view = { idx: 1, app: null, title: null };
  const s = marginState(view, AT, { sync: 'sync !', goal: 'Ship v2 · 3d', wifi: 'wifi', battery: '82%' });
  assert.equal(s.right.sync, 'sync !');
  assert.equal(s.right.text, 'sync !  Ship v2 · 3d  wifi  82%  Sun 18 Oct');
  assert.equal(marginState(view, AT, { sync: '', goal: 'Ship v2 · 3d', wifi: 'wifi', battery: '82%' }).right.text, 'Ship v2 · 3d  wifi  82%  Sun 18 Oct');
});

test('wifi is named only when there is a Wi-Fi device', () => {
  assert.equal(wifiText([{ wifi: true, connected: true }]), 'wifi');
  assert.equal(wifiText([{ wifi: false, connected: true }, { wifi: true, connected: false }]), 'no wifi');
  assert.equal(wifiText([{ wifi: false, connected: true }]), '');
});
