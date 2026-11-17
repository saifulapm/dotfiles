import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ICONS, liveState, liveWidth, ONE_LINE_MAX } from './island-live.mjs';

const AT = new Date(2026, 10, 18, 14, 32);
const live = (mode, slot) => liveState(mode, { [mode]: slot }, AT);

test('each icon is a filled Material Design glyph from the Symbols Nerd Font', () => {
  // The codepoints read from SymbolsNerdFontMono-Regular.ttf's own cmap and post names (md-music, md-volume_high, ...).
  assert.deepEqual(ICONS, {
    music: '\u{F075A}',
    volume: '\u{F057E}',
    volumeOff: '\u{F0581}',
    brightness: '\u{F00DF}',
    mic: '\u{F036C}',
    cast: '\u{F0118}',
    record: '\u{F044A}',
    robot: '\u{F06A9}',
    upload: '\u{F0552}',
    download: '\u{F01DA}',
    headphones: '\u{F02CB}',
    eyedropper: '\u{F020A}',
    check: '\u{F012C}',
    alert: '\u{F0028}',
    calendar: '\u{F00ED}',
    play: '\u{F040A}',
    pause: '\u{F03E4}',
    previous: '\u{F04AE}',
    next: '\u{F04AD}',
  });
});

test('now playing is a music icon and the track title, with the clock at the right', () => {
  assert.deepEqual(live('playing', { title: 'Paranoid Android', artist: 'Radiohead' }), { icon: ICONS.music, text: 'Paranoid Android', tail: '', tone: 'normal', bar: null, swatch: '', clock: '14:32' });
  assert.equal(live('playing', { title: '', artist: 'Radiohead' }).text, 'Radiohead');
});

test('a volume key at 45% is a speaker, a pill bar filled to 45% and 45%; brightness a sun', () => {
  const v = live('osd', { kind: 'volume', value: 45 });
  assert.deepEqual([v.icon, v.text, v.bar, v.tone], [ICONS.volume, '45%', 45, 'normal']);
  assert.equal(live('osd', { kind: 'volume', value: 0 }).icon, ICONS.volumeOff);
  assert.equal(live('osd', { kind: 'brightness', value: 70 }).icon, ICONS.brightness);
});

test('the mic, LIVE, a recording and a notice take the danger tone', () => {
  const rec = live('recording', '00:05');
  assert.deepEqual([rec.icon, rec.text, rec.tone], [ICONS.record, '00:05', 'danger']);
  assert.deepEqual([live('mic', ['Firefox', 'Zoom']).icon, live('mic', ['Firefox', 'Zoom']).text, live('mic', ['Firefox']).tone], [ICONS.mic, 'Firefox +1', 'danger']);
  const share = live('sharing', [{ target: 'screen', active: true }]);
  assert.deepEqual([share.icon, share.text, share.tone], [ICONS.cast, 'LIVE SCREEN', 'danger']);
  const notice = liveState('rest', { notice: 'theme failed' }, AT);
  assert.deepEqual([notice.icon, notice.text, notice.tone], [ICONS.alert, 'theme failed', 'danger']);
});

test('an agent lease is a robot, the agent and the time left; its last minute takes the danger tone', () => {
  const l = live('lease', { who: 'claude', left: 272000 });
  assert.deepEqual([l.icon, l.text, l.tail, l.tone], [ICONS.robot, 'claude', '4:32', 'normal']);
  assert.deepEqual([live('lease', { who: 'claude', left: 59000 }).tail, live('lease', { who: 'claude', left: 59000 }).tone], ['0:59', 'danger']);
});

test('a send is an upload, the files and where, and a pill bar', () => {
  const s = live('sending', { count: 2, to: 'nuc', pct: 48 });
  assert.deepEqual([s.icon, s.text, s.bar], [ICONS.upload, '2 files to nuc', 48]);
});

test('a download of 3 is a download icon, 1 / 3, its percent and a pill bar; a single one reads its title', () => {
  const d = live('downloading', { n: 1, total: 3, list: 'Mix', title: 'Song', pct: 40, kind: 'audio', failure: null });
  assert.deepEqual([d.icon, d.text, d.tail, d.bar], [ICONS.download, '1 / 3', '40%', 40]);
  assert.equal(live('downloading', { n: 1, total: 1, list: '', title: 'Song', pct: 0, kind: 'audio', failure: null }).text, 'Song');
  const f = live('downloading', { n: 1, total: 1, list: '', title: '', pct: 0, kind: '', failure: { title: 'Song', reason: 'private video' } });
  assert.deepEqual([f.icon, f.text, f.tone], [ICONS.alert, 'Song · private video', 'danger']);
});

test('Bluetooth, a capture and a toast', () => {
  const b = live('btConnect', { name: 'WH-1000XM4', address: 'AA:BB', battery: 0.8 });
  assert.deepEqual([b.icon, b.text, b.tail], [ICONS.headphones, 'WH-1000XM4', '80%']);
  assert.equal(live('btConnect', { name: 'Keys', address: 'AA:BB', battery: null }).tail, '');
  const c = live('capture', { kind: 'colour', title: 'Copied', detail: '#C8381E', swatch: '#C8381E' });
  assert.deepEqual([c.icon, c.text, c.swatch], [ICONS.eyedropper, '#C8381E', '#C8381E']);
  const o = live('capture', { kind: 'ocr', title: 'Text copied', detail: '214 characters', swatch: null });
  assert.deepEqual([o.icon, o.text, o.swatch], [ICONS.check, 'Text copied · 214 characters', '']);
  assert.deepEqual([live('toast', 'Captured').icon, live('toast', 'Captured').text], [ICONS.check, 'Captured']);
});

test('a mode with no one-line state, rest or a card, has none', () => {
  assert.equal(liveState('rest', {}, AT), null);
  assert.equal(liveState('notification', { notification: { summary: 'hi' } }, AT), null);
});

test('text is one line: controls and bidi marks go', () => {
  assert.equal(live('playing', { title: 'a‮b\nc', artist: '' }).text, 'ab c');
});

test('the box is the icon, the text, the tail, the bar and the clock, never wider than the widest line', () => {
  assert.equal(liveWidth({ text: 100, tail: 0, bar: false, swatch: false, clock: 40 }), 14 + 14 + 8 + 100 + 16 + 40 + 14);
  assert.equal(liveWidth({ text: 100, tail: 30, bar: true, swatch: false, clock: 40 }), 14 + 14 + 8 + 100 + 8 + 30 + 8 + 56 + 16 + 40 + 14);
  assert.equal(liveWidth({ text: 5000, tail: 0, bar: false, swatch: false, clock: 40 }), ONE_LINE_MAX);
});
