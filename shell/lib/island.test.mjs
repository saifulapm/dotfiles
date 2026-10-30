import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pick, islandText, boxWidth, MAX_WIDTH, monthGrid, shiftMonth, recordingText, springCurve, islandMotion, isCompact, ease, captureOf, shareRow, shareRowText, commNames, stopSessions, brightnessStep, micApps } from './island.mjs';

const AT = new Date(2026, 9, 18, 14, 32);
const note = { app: 'notify-send', summary: 'hi', body: '' };
const question = { id: 'Q1', text: 'Import the feed?', options: ['Import now', 'Later'] };

test('with nothing live the island rests', () => {
  assert.equal(pick({}), 'rest');
});

test('a question outranks every other slot', () => {
  const all = { question, calendar: true, notification: note, recording: '00:12', osd: { kind: 'volume', value: 40 }, toast: 'Captured', playing: { title: 'Track', artist: 'Artist' } };
  assert.equal(pick(all), 'question');
});

test('below a question: notification, recording, osd, toast, a send, then playing', () => {
  const slots = { notification: note, recording: '00:12', osd: { kind: 'volume', value: 40 }, toast: 'Captured', sending: { count: 2, to: 'nuc', pct: 48 }, playing: { title: 'T', artist: 'A' } };
  const order = [];
  for (const k of ['notification', 'recording', 'osd', 'toast', 'sending', 'playing']) {
    order.push(pick(slots));
    delete slots[k];
  }
  assert.deepEqual(order, ['notification', 'recording', 'osd', 'toast', 'sending', 'playing']);
  assert.equal(pick(slots), 'rest');
});

test('the calendar opened from rest gives way only to a question', () => {
  assert.equal(pick({ calendar: true, notification: note }), 'calendar');
  assert.equal(pick({ calendar: true, question }), 'question');
});

test('each mode reads as one line of text', () => {
  assert.equal(islandText('rest', {}, AT), '14:32');
  assert.equal(islandText('rest', { notice: 'theme broken: invalid theme.toml' }, AT), 'theme broken: invalid theme.toml');
  assert.equal(islandText('notification', { notification: { app: 'mail', summary: 'hi', body: 'see you' } }, AT), 'mail · hi · see you');
  assert.equal(islandText('notification', { notification: note }, AT), 'notify-send · hi');
  assert.equal(islandText('osd', { osd: { kind: 'volume', value: 45 } }, AT), 'Volume 45%');
  assert.equal(islandText('osd', { osd: { kind: 'brightness', value: 70 } }, AT), 'Brightness 70%');
  assert.equal(islandText('playing', { playing: { title: 'Track', artist: 'Artist' } }, AT), 'Track — Artist  14:32');
  assert.equal(islandText('playing', { playing: { title: 'Track', artist: '' } }, AT), 'Track  14:32');
  assert.equal(islandText('question', { question }, AT), 'Import the feed?  [1] Import now  [2] Later');
  assert.equal(islandText('toast', { toast: 'Captured' }, AT), 'Captured');
  assert.equal(islandText('recording', { recording: '00:12' }, AT), 'REC 00:12');
});

test('the box never grows past 560 px', () => {
  assert.equal(MAX_WIDTH, 560);
  assert.equal(boxWidth(100), 100);
  assert.equal(boxWidth(5000), 560);
});

test('the month grid starts on Monday and pads the first and last weeks', () => {
  const g = monthGrid(2026, 9);
  assert.equal(g.title, 'October 2026');
  assert.deepEqual(g.weeks[0], [null, null, null, 1, 2, 3, 4]);
  assert.deepEqual(g.weeks.at(-1), [26, 27, 28, 29, 30, 31, null]);
  assert.equal(g.weeks.length, 5);
  assert.deepEqual(g.cells, [].concat(...g.weeks));
});

test('a month that starts on Sunday puts the 1st last in its first week', () => {
  assert.deepEqual(monthGrid(2026, 1).weeks[0], [null, null, null, null, null, null, 1]);
  assert.deepEqual(monthGrid(2026, 1).weeks.at(-1).slice(0, 6), [23, 24, 25, 26, 27, 28]);
});

test('a board that starts its weeks on Sunday shifts the grid and names the month and year apart', () => {
  const g = monthGrid(2026, 9, 0);
  assert.deepEqual(g.weeks[0], [null, null, null, null, 1, 2, 3]);
  assert.deepEqual(g.weeks.at(-1), [25, 26, 27, 28, 29, 30, 31]);
  assert.deepEqual([g.month, g.abbr, g.year, g.title], ['October', 'Oct', 2026, 'October 2026']);
});

test('the calendar reads as its month, and moving a month crosses the year', () => {
  assert.equal(islandText('calendar', { calendar: { year: 2026, month: 9 } }, AT), 'October 2026');
  assert.deepEqual(shiftMonth(2026, 11, 1), { year: 2027, month: 0 });
  assert.deepEqual(shiftMonth(2026, 0, -1), { year: 2025, month: 11 });
});

test('a recording reads minutes and seconds since it started', () => {
  assert.equal(recordingText(1000, 1000), '00:00');
  assert.equal(recordingText(1000, 13999), '00:12');
  assert.equal(recordingText(0, 61 * 60 * 1000), '61:00');
});

// The approved prototype's numbers: stiffness 260 and damping 0.70 open, 1.5 times stiffer and 0.08 more damped close.
test('Artboard: the spring opens in 611 ms and closes in 456 ms', () => {
  const m = islandMotion('spring');
  assert.deepEqual([m.open.ms, m.close.ms], [611, 456]);
  assert.deepEqual(m.swap, { kind: 'blur', inMs: 306, outMs: 130, delay: 60, blur: 6 });
});

test('a spring curve starts at 0, overshoots and ends at rest', () => {
  const { points } = springCurve(260, 0.7);
  assert.equal(points.length, 61);
  assert.deepEqual([points[0], points[60]], [0, 1]);
  assert.ok(points.some((y) => y > 1));
});

test('a critically damped spring never overshoots', () => {
  assert.ok(springCurve(260, 1).points.every((y) => y <= 1));
});

test('Paper is snappy: 120 ms open, 96 ms close, past halfway a quarter of the way in', () => {
  const m = islandMotion('snappy');
  assert.deepEqual([m.open.ms, m.close.ms, m.swap.kind], [120, 96, 'drop']);
  assert.deepEqual([m.open.points[0], m.open.points[60]], [0, 1]);
  assert.ok(ease(m.open.points, 0.25) > 0.5);
});

test('ease reads between samples and keeps the overshoot', () => {
  const linear = islandMotion('linear').open.points;
  assert.deepEqual([ease(linear, 0), ease(linear, 0.5), ease(linear, 1)], [0, 0.5, 1]);
  const spring = springCurve(260, 0.7).points;
  assert.ok([0.3, 0.35, 0.4, 0.45].some((t) => ease(spring, t) > 1));
  assert.equal(ease(spring, 2), 1);
});

test('Blueprint is linear: 150 ms open, 120 ms close, and its content scans in', () => {
  const m = islandMotion('linear');
  assert.deepEqual([m.open.ms, m.close.ms, m.swap.kind], [150, 120, 'scan']);
});

test('every motion on the theme menu has an island motion, and no token means none', () => {
  for (const motion of ['spring', 'snappy', 'ease', 'typewriter', 'linear']) assert.ok(islandMotion(motion), motion);
  assert.equal(islandMotion(undefined), null);
});

test('the one-line modes close; the cards open', () => {
  assert.deepEqual(['rest', 'playing', 'recording', 'toast'].map(isCompact), [true, true, true, true]);
  assert.deepEqual(['notification', 'question', 'calendar', 'osd'].map(isCompact), [false, false, false, false]);
});

test("an agent's lease sits just below LIVE, so a share shows while an agent holds the session (X1WV1TFF)", () => {
  const lease = { who: 'claude', left: 60000 };
  assert.equal(pick({ question: { text: 'q', options: [] }, lease }), 'question');
  assert.equal(pick({ lease, sharing: [share()] }), 'sharing');
  assert.equal(pick({ lease, notification: { app: 'a' } }), 'notification');
  assert.equal(pick({ lease, recording: '00:12', osd: { kind: 'volume', value: 1 } }), 'lease');
  assert.equal(isCompact('lease'), true);
});

test('Mod+I during a lease opens its card, which only a question outranks', () => {
  const lease = { who: 'claude', left: 60000 };
  assert.equal(pick({ leaseCard: lease, lease }), 'leaseCard');
  assert.equal(pick({ question: { text: 'q', options: [] }, leaseCard: lease, lease }), 'question');
  assert.equal(isCompact('leaseCard'), false);
});

test('a send reads how many files go where and how far it got, on one line', () => {
  assert.equal(islandText('sending', { sending: { count: 2, to: 'nuc', pct: 48 } }, AT), 'Sending 2 files to nuc · 48%');
  assert.equal(islandText('sending', { sending: { count: 1, to: 'nu\nc', pct: 0 } }, AT), 'Sending 1 file to nu c · 0%');
  assert.equal(isCompact('sending'), true);
});

test('a capture result shows just below a toast, with its kind, title and detail', () => {
  const ocr = captureOf('ocr', 'Text copied', '214 characters');
  assert.equal(pick({ toast: 'Captured', capture: ocr }), 'toast');
  assert.equal(pick({ capture: ocr, sending: { count: 1, to: 'nuc', pct: 1 } }), 'capture');
  assert.equal(isCompact('capture'), true);
  assert.deepEqual(ocr, { kind: 'ocr', title: 'Text copied', detail: '214 characters', swatch: null });
  assert.deepEqual(captureOf('colour', 'Copied', '#c8381e'), { kind: 'colour', title: 'Copied', detail: '#c8381e', swatch: '#C8381E' });
  assert.equal(islandText('capture', { capture: ocr }, AT), 'Text copied · 214 characters');
  assert.equal(islandText('capture', { capture: captureOf('colour', 'Copied', '#C8381E') }, AT), 'Copied #C8381E');
  assert.equal(islandText('capture', { capture: captureOf('qr', 'QR code copied', '') }, AT), 'QR code copied');
  // A miss copies nothing, so it has no title, only the words.
  assert.equal(islandText('capture', { capture: captureOf('ocr', '', 'No text found') }, AT), 'No text found');
});

test('a capture from any caller is one plain line, a swatch only for a colour hex, and only a known kind', () => {
  assert.equal(captureOf('ocr', 'Text copied', 'a\nb‮c').detail, 'a bc');
  assert.equal(captureOf('ocr', 'Copied', '#C8381E').swatch, null);
  assert.equal(captureOf('annotate', 'Copied', ''), null);
  assert.equal(captureOf('ocr', 'Ship\nv2\u202Etoday\u001b[31m\u0085x\u200f', '').title, 'Ship v2today [31m x');
  assert.equal(captureOf('ocr', 'x'.repeat(200), '').title, 'x'.repeat(200));
  assert.equal(captureOf('colour', ' \n ', ''), null);
  assert.equal(captureOf('colour', 'Copied', 'red').swatch, null);
  assert.equal(captureOf('colour', 'Copied', '#C8381E; x').swatch, null);
});

const share = (o) => ({ stream: 1, session: 1, kind: 'PipeWire', target: 'screen', app: null, active: true, pid: null, ...o });

test('sharing sits below a notification and above the recording timer (7WVQMXDS)', () => {
  const slots = { question, leaseCard: true, lease: true, calendar: true, notification: note, sharing: [share()], recording: '00:12', osd: { kind: 'volume', value: 40 }, toast: 'Captured', capture: true, sending: true, playing: true };
  const order = [];
  for (const k of ['question', 'leaseCard', 'calendar', 'notification', 'sharing', 'lease', 'recording', 'osd', 'toast', 'capture', 'sending', 'playing']) {
    order.push(pick(slots));
    delete slots[k];
  }
  assert.deepEqual(order, ['question', 'leaseCard', 'calendar', 'notification', 'sharing', 'lease', 'recording', 'osd', 'toast', 'capture', 'sending', 'playing']);
  assert.equal(isCompact('sharing'), true);
});

test('the sharing card opened by Mod+I holds against a notification, like the calendar', () => {
  assert.equal(pick({ sharingCard: [share()], notification: note, sharing: [share()] }), 'sharingCard');
  assert.equal(pick({ sharingCard: [share()], question }), 'question');
  assert.equal(isCompact('sharingCard'), false);
});

test('sharing reads LIVE and what is seen; two or more read as a count (M5W7ZJ8V, SN5W2JY5)', () => {
  const live = (...s) => islandText('sharing', { sharing: s }, AT);
  assert.equal(live(share()), 'LIVE SCREEN');
  assert.equal(live(share({ target: 'window', app: 'foot' })), 'LIVE FOOT');
  assert.equal(live(share({ target: 'window', app: null })), 'LIVE WINDOW');
  assert.equal(live(share({ target: 'nothing' })), 'LIVE NOTHING');
  assert.equal(live(share({ active: false })), 'LIVE PAUSED');
  assert.equal(live(share({ target: 'nothing', active: false })), 'LIVE PAUSED');
  assert.equal(live(share(), share({ stream: 2, active: false })), 'LIVE ×2');
  assert.equal(live(share({ target: 'window', app: 'a\nb‮evil\u001b[31m' })), 'LIVE A BEVIL [31M');
  // An app id is the app's to choose, so one with nothing left to draw reads as a window.
  assert.equal(live(share({ target: 'window', app: '' })), 'LIVE WINDOW');
  assert.equal(live(share({ target: 'window', app: '\n\u202E\u001b' })), 'LIVE WINDOW');
});

test('each card row is its target, who watches, and a stop only on PipeWire (MGX0WWS8, XPRY7NFD)', () => {
  const names = { 4242: 'wf-recorder' };
  assert.deepEqual(shareRow(share({ kind: 'WlrScreencopy', pid: 4242 }), names), { target: 'SCREEN', watcher: 'wf-recorder', stop: false });
  assert.deepEqual(shareRow(share(), names), { target: 'SCREEN', watcher: 'portal share', stop: true });
  assert.deepEqual(shareRow(share({ target: 'window', app: 'x'.repeat(200) }), names).target, 'X'.repeat(200));
  // A process names itself, and its 15 bytes of comm can hold any control or bidi mark.
  assert.equal(shareRow(share({ kind: 'WlrScreencopy', pid: 7 }), { 7: 'a\nb‮\u001b[31m' }).watcher, 'a b [31m');
  assert.equal(shareRow(share({ kind: 'WlrScreencopy', pid: 8 }), names).watcher, 'pid 8');
});

test('Enter stops each PipeWire session once and leaves screencopy alone', () => {
  const all = [share({ stream: 1, session: 5 }), share({ stream: 2, session: 5 }), share({ stream: 3, session: 6 }), share({ stream: 4, session: 7, kind: 'WlrScreencopy', pid: 9 })];
  assert.deepEqual(stopSessions(all), [5, 6]);
  assert.deepEqual(stopSessions([share({ kind: 'WlrScreencopy', pid: 9 })]), []);
});

test('a card row reads its target, who watches, then ↵ stop on PipeWire', () => {
  assert.equal(shareRowText({ target: 'SCREEN', watcher: 'wf-recorder', stop: false }), 'SCREEN  wf-recorder');
  assert.equal(shareRowText({ target: 'SCREEN', watcher: 'portal share', stop: true }), 'SCREEN  portal share  ↵ stop');
});

test("each pid's comm reads back by pid, with only its own trailing newline taken off", () => {
  assert.deepEqual(commNames('4242\twf-recorder\n\u0000'), { 4242: 'wf-recorder' });
  assert.deepEqual(commNames('7\ta\nb\n\u00008\tobs\n\u0000'), { 7: 'a\nb', 8: 'obs' });
  // A pid gone before it was read has no comm, and stays unnamed.
  assert.deepEqual(commNames('9\t\u0000'), {});
  assert.deepEqual(commNames(''), {});
});

test('brightness takes a step like 5%+ or an absolute 1% to 100%, and nothing else', () => {
  for (const step of ['5%+', '5%-', '1%+', '1%', '100%', '45%']) assert.equal(brightnessStep(step), true, step);
  for (const step of ['0%', '101%', '5;rm', '5', '%', '-5%', '5%+;rm', '']) assert.equal(brightnessStep(step), false, step);
});

// A capture stream as ControlAudio-style reads give it: Quickshell hands properties over as strings.
const rec = (id, props = {}) => ({ id, capture: true, props: { 'object.serial': String(100 + id), ...props } });
const from = (source, target, active = true) => ({ source, target, active });
const MIC = 7;

test('an app recording from the default source puts its name in the mic slot', () => {
  const streams = [rec(40, { 'application.name': 'Test Recorder' })];
  assert.deepEqual(micApps(streams, [from(MIC, 40)], MIC, 0), ['Test Recorder']);
  assert.equal(islandText('mic', { mic: ['Test Recorder'] }, AT), '● MIC · Test Recorder');
});

test('with two apps the newest by serial is named and the rest counted', () => {
  const streams = [rec(52, { 'application.name': 'Other', 'object.serial': '900' }), rec(40, { 'application.name': 'Test Recorder', 'object.serial': '300' })];
  const apps = micApps(streams, [from(MIC, 40), from(MIC, 52)], MIC, 0);
  assert.deepEqual(apps, ['Other', 'Test Recorder']);
  assert.equal(islandText('mic', { mic: apps }, AT), '● MIC · Other +1');
  // Node ids are reused, serials are not, so a reused low id that is newer still comes first.
  const reused = [rec(40, { 'application.name': 'Old', 'object.serial': '300' }), rec(3, { 'application.name': 'New', 'object.serial': '901' })];
  assert.deepEqual(micApps(reused, [from(MIC, 40), from(MIC, 3)], MIC, 0), ['New', 'Old']);
});

test('without an application name the node description names it, on one line', () => {
  assert.deepEqual(micApps([rec(40, { 'node.description': 'Voice\nMemo' })], [from(MIC, 40)], MIC, 0), ['Voice Memo']);
});

test('only an active link from the default source into a capture stream counts', () => {
  const s = [rec(40, { 'application.name': 'A' })];
  assert.deepEqual(micApps(s, [from(MIC, 40, false)], MIC, 0), []);
  assert.deepEqual(micApps(s, [from(8, 40)], MIC, 0), []);
  assert.deepEqual(micApps([{ ...s[0], capture: false }], [from(MIC, 40)], MIC, 0), []);
  assert.deepEqual(micApps(s, [from(MIC, 40)], -1, 0), []);
});

test("monitor and passive streams and the shell's own recorder never count", () => {
  const links = [from(MIC, 40)];
  for (const props of [{ 'stream.monitor': 'true' }, { 'node.passive': 'true' }, { 'media.category': 'Monitor' }, { 'application.process.id': '4242' }])
    assert.deepEqual(micApps([rec(40, { 'application.name': 'A', ...props })], links, MIC, 4242), [], JSON.stringify(props));
  assert.deepEqual(micApps([rec(40, { 'application.name': 'A', 'stream.monitor': 'false', 'node.passive': 'false', 'application.process.id': '17' })], links, MIC, 4242), ['A']);
});

test('a link whose target has gone, read as id -1, counts nothing', () => {
  assert.deepEqual(micApps([rec(40, { 'application.name': 'A' })], [from(MIC, -1), from(-1, 40)], MIC, 0), []);
});

test('the mic slot shows right after sharing, above the lease and the recording timer, and is compact', () => {
  const mic = ['A'];
  assert.equal(pick({ sharing: [share()], mic }), 'sharing');
  assert.equal(pick({ notification: note, mic }), 'notification');
  assert.equal(pick({ mic, lease: { who: 'claude', left: 1 }, recording: '00:01', osd: { kind: 'volume', value: 1 } }), 'mic');
  assert.equal(pick({ mic: null, recording: '00:01' }), 'recording');
  assert.equal(isCompact('mic'), true);
});

test('a device connecting shows right after the OSD, compact, as its connect text', () => {
  const btConnect = { name: 'AirPods', address: 'A', battery: 0.8 };
  assert.equal(pick({ osd: { kind: 'volume', value: 1 }, btConnect }), 'osd');
  assert.equal(pick({ recording: '00:01', btConnect }), 'recording');
  assert.equal(pick({ btConnect, toast: 'Captured', playing: { title: 't' } }), 'btConnect');
  assert.equal(islandText('btConnect', { btConnect }, AT), 'AirPods connected · 80%');
  assert.equal(isCompact('btConnect'), true);
});

test('one app with two capture streams is one app in the mic slot', () => {
  const streams = [rec(40, { 'application.name': 'Chromium', 'object.serial': '300' }), rec(41, { 'application.name': 'Chromium', 'object.serial': '301' })];
  assert.deepEqual(micApps(streams, [from(MIC, 40), from(MIC, 41)], MIC, 0), ['Chromium']);
  const three = [...streams, rec(42, { 'application.name': 'Zoom', 'object.serial': '200' })];
  assert.equal(islandText('mic', { mic: micApps(three, [from(MIC, 40), from(MIC, 41), from(MIC, 42)], MIC, 0) }, AT), '● MIC · Chromium +1');
});
