import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addEntry, parseStore, storeText, LIMIT, visible, group, clampSelected, filesOf, fileUri, uriList, chipLabel, dragPayload, holdMs, setAside, resumeMs, shows, toggle, cycleStay, ruleText, ruleOf, chipsOf, raiseTarget } from './notifs.mjs';

const entry = (n, app = 'notify-send') => ({ key: `k${n}`, app, summary: `n ${n}`, body: '', critical: false, time: 1000 + n, actions: [] });

test('the newest entry goes first', () => {
  const h = addEntry(addEntry([], entry(1)), entry(2));
  assert.deepEqual(h.map((e) => e.summary), ['n 2', 'n 1']);
});

test('the history keeps 200 entries and drops the oldest', () => {
  assert.equal(LIMIT, 200);
  let h = [];
  for (let i = 1; i <= 201; i++) h = addEntry(h, entry(i));
  assert.equal(h.length, 200);
  assert.equal(h[0].summary, 'n 201');
  assert.equal(h.at(-1).summary, 'n 2');
});

test('the store round-trips the history, Do Not Disturb and the per-app rules', () => {
  const h = [entry(2), entry(1)];
  const rules = { T: { muted: true, dnd: true, stays: 10000 }, slack: { stays: 0 } };
  assert.deepEqual(parseStore(storeText({ dnd: true, rules, history: h })), { dnd: true, rules, history: h });
  assert.deepEqual(Object.keys(JSON.parse(storeText({ dnd: true, rules, history: h }))), ['dnd', 'rules', 'history']);
});

test('a store saved before per-app rules loads its history unchanged, with no rules', () => {
  const h = [entry(2), entry(1)];
  assert.deepEqual(parseStore(JSON.stringify({ dnd: true, history: h })), { dnd: true, rules: {}, history: h });
});

test('a stored rule that is not one m, i or s could set is dropped', () => {
  const rules = { T: { muted: true, stays: 7000 }, U: 'muted', V: { stays: 0 }, W: {}, X: { dnd: 1 }, Y: null };
  assert.deepEqual(parseStore(JSON.stringify({ history: [], rules })).rules, { T: { muted: true }, V: { stays: 0 } });
  assert.deepEqual(parseStore(JSON.stringify({ history: [], rules: [] })).rules, {});
});

test('a missing, broken or foreign store reads as empty', () => {
  for (const text of ['', '{', '[]', '{"history":3}', 'null']) assert.deepEqual(parseStore(text), { dnd: false, rules: {}, history: [] });
});

test('a stored entry missing its fields is dropped, and a long store is cut to 200', () => {
  const many = Array.from({ length: 250 }, (_, i) => entry(250 - i));
  const s = parseStore(JSON.stringify({ dnd: 'yes', history: [{ app: 1 }, ...many] }));
  assert.equal(s.dnd, false);
  assert.equal(s.history.length, 200);
  assert.equal(s.history[0].summary, 'n 250');
});

const from = (app, summary, time, body = '') => ({ key: `${app}-${time}`, app, summary, body, critical: false, time, actions: [] });
const shape = (groups) => groups.map((g) => [g.app, g.entries.map((e) => e.summary)]);

test('each app gets one group, groups by their newest entry, entries newest first', () => {
  const history = [from('chat', 'c3', 50), from('mail', 'm2', 40), from('chat', 'c2', 30), from('mail', 'm1', 20), from('chat', 'c1', 10)];
  assert.deepEqual(shape(group(history)), [
    ['chat', ['c3', 'c2', 'c1']],
    ['mail', ['m2', 'm1']],
  ]);
  assert.deepEqual(shape(group([from('mail', 'm1', 20), from('chat', 'c1', 30)])), [
    ['chat', ['c1']],
    ['mail', ['m1']],
  ]);
});

test('search matches app, summary or body, ignoring case', () => {
  const history = [from('Chat', 'lunch?', 30), from('mail', 'Invoice', 20, 'due Friday'), from('mail', 'hello', 10)];
  const found = (q) => visible(history, q).map((e) => e.summary);
  assert.deepEqual(found(''), ['lunch?', 'Invoice', 'hello']);
  assert.deepEqual(found('CHAT'), ['lunch?']);
  assert.deepEqual(found('invoice'), ['Invoice']);
  assert.deepEqual(found('friday'), ['Invoice']);
  assert.deepEqual(found('nothing'), []);
});

test('the selection stays in range after a removal', () => {
  assert.equal(clampSelected(2, 2), 1);
  assert.equal(clampSelected(1, 3), 1);
  assert.equal(clampSelected(0, 0), 0);
  assert.equal(clampSelected(-1, 3), 0);
});

test('a store with entries sharing a key keeps only the first, so a dismiss takes one row', () => {
  const s = parseStore(JSON.stringify({ dnd: false, history: [entry(3), Object.assign(entry(2), { key: 'k3' }), entry(1)] }));
  assert.deepEqual(s.history.map((e) => e.summary), ['n 3', 'n 1']);
});

const HOME = '/home/saiful';

test('x-dots-files gives its path, URI and chip', () => {
  const files = filesOf({ 'x-dots-files': '/home/saiful/Downloads/IMG_2041.HEIC' }, HOME);
  assert.deepEqual(files, ['/home/saiful/Downloads/IMG_2041.HEIC']);
  assert.equal(fileUri(files[0]), 'file:///home/saiful/Downloads/IMG_2041.HEIC');
  assert.equal(chipLabel(files), 'HEIC');
  assert.equal(chipLabel(['/home/saiful/Downloads/README']), 'FILE');
});

test('a name with spaces, # and non-ASCII encodes per segment', () => {
  const path = '/home/saiful/Downloads/my photo #1 é.jpg';
  const uri = fileUri(path);
  assert.equal(uri, 'file:///home/saiful/Downloads/my%20photo%20%231%20%C3%A9.jpg');
  assert.equal(decodeURIComponent(uri.slice('file://'.length)), path);
});

test('an image-path that is not a user file gives no files', () => {
  for (const p of ['/tmp/chromium-xyz.png', '/usr/share/icons/hicolor/48x48/apps/x.png', '/usr/share/pixmaps/x.png', HOME + '/.local/share/icons/x.png', HOME + '/.icons/x.png', 'dialog-information', '/home/saiful/../tmp/x']) {
    assert.deepEqual(filesOf({ 'image-path': p }, HOME), [], p);
  }
});

test('an image-path file URI is decoded, and image_path works too', () => {
  const want = ['/home/saiful/Pictures/Screenshots/Screenshot from 2026.png'];
  assert.deepEqual(filesOf({ 'image-path': 'file:///home/saiful/Pictures/Screenshots/Screenshot%20from%202026.png' }, HOME), want);
  assert.deepEqual(filesOf({ image_path: '/home/saiful/Pictures/a.png' }, HOME), ['/home/saiful/Pictures/a.png']);
});

test('x-dots-files wins over image-path and skips blank, relative and /tmp lines', () => {
  const hints = { 'x-dots-files': '/home/saiful/Downloads/a.txt\n\nrel/b.txt\n/tmp/c.txt\n/home/saiful/Downloads/d.txt', 'image-path': '/home/saiful/Pictures/x.png' };
  assert.deepEqual(filesOf(hints, HOME), ['/home/saiful/Downloads/a.txt', '/home/saiful/Downloads/d.txt']);
});

test('three files give a CRLF uri-list and a count chip', () => {
  const files = filesOf({ 'x-dots-files': '/home/saiful/Downloads/a.txt\n/home/saiful/Downloads/b b.txt\n/home/saiful/Downloads/c.txt' }, HOME);
  assert.equal(files.length, 3);
  assert.equal(uriList(files), 'file:///home/saiful/Downloads/a.txt\r\nfile:///home/saiful/Downloads/b%20b.txt\r\nfile:///home/saiful/Downloads/c.txt\r\n');
  assert.equal(chipLabel(files), '3 FILES');
});

test('an entry drags its files as a uri-list, else its body as text', () => {
  assert.deepEqual(dragPayload({ body: 'hi', files: ['/home/saiful/Downloads/a.txt'] }), { mime: 'text/uri-list', data: 'file:///home/saiful/Downloads/a.txt\r\n' });
  assert.deepEqual(dragPayload({ body: 'hi' }), { mime: 'text/plain', data: 'hi' });
  assert.deepEqual(dragPayload({ body: 'hi', files: [] }), { mime: 'text/plain', data: 'hi' });
});

test('parseStore keeps a valid files array and drops a malformed one', () => {
  const good = Object.assign(entry(1), { files: ['/home/saiful/Downloads/a.txt'] });
  assert.deepEqual(parseStore(storeText({ dnd: false, history: [good] })).history, [good]);
  for (const files of ['/home/saiful/a', ['rel/a'], ['/a', 3], [null]]) {
    const h = parseStore(JSON.stringify({ history: [Object.assign(entry(2), { files })] })).history;
    assert.equal(h.length, 1);
    assert.equal('files' in h[0], false);
  }
});

test("an app's timeout decides the hold: -1 is 5 s, 0 is until dismissed, a positive one as given", () => {
  assert.equal(holdMs(Object.assign(entry(1), { timeout: -1 })), 5000);
  assert.equal(holdMs(Object.assign(entry(1), { timeout: 0 })), 0);
  assert.equal(holdMs(Object.assign(entry(1), { timeout: 2000 })), 2000);
});

test('a critical with no timeout of its own holds until dismissed; one with a timeout keeps it', () => {
  assert.equal(holdMs(Object.assign(entry(1), { critical: true, timeout: -1 })), 0);
  assert.equal(holdMs(Object.assign(entry(1), { critical: true, timeout: 3000 })), 3000);
});

const critical = (n) => Object.assign(entry(n), { critical: true, timeout: -1 });

test('a critical that stays until dismissed is set aside when a newer notification takes the island, newest first', () => {
  assert.deepEqual(setAside([], critical(1), 'k2').map((e) => e.key), ['k1']);
  assert.deepEqual(setAside([critical(1)], critical(2), 'k3').map((e) => e.key), ['k2', 'k1']);
  assert.deepEqual(setAside([critical(2)], critical(1), 'k3').map((e) => e.key), ['k2', 'k1']);
});

test('a normal notification, a critical with its own timeout, or no notification at all is not set aside', () => {
  assert.deepEqual(setAside([], Object.assign(entry(1), { timeout: -1 }), 'k2'), []);
  assert.deepEqual(setAside([], Object.assign(critical(1), { timeout: 3000 }), 'k2'), []);
  assert.deepEqual(setAside([], null, 'k2'), []);
});

test('the notification taking the island leaves the set-aside ones, as a replace of itself does', () => {
  assert.deepEqual(setAside([critical(1), critical(2)], null, 'k1').map((e) => e.key), ['k2']);
  assert.deepEqual(setAside([], critical(1), 'k1'), []);
});

test('a paused hold resumes with the time it had left, at least 1.5 s', () => {
  const normal = Object.assign(entry(1), { timeout: -1 });
  assert.equal(resumeMs(normal, 3200), 3200);
  assert.equal(resumeMs(normal, 400), 1500);
});

test('a hold paused as it ran out still resumes, and one until dismissed never does', () => {
  assert.equal(resumeMs(Object.assign(entry(1), { timeout: -1 }), 0), 1500);
  assert.equal(resumeMs(Object.assign(entry(1), { timeout: -1 }), -20), 1500);
  assert.equal(resumeMs(Object.assign(entry(1), { critical: true, timeout: -1 }), 0), 0);
  assert.equal(resumeMs(Object.assign(entry(1), { timeout: 0 }), 0), 0);
});

test('a muted app goes to the history only, its criticals too, and Do Not Disturb still lets criticals through', () => {
  const muted = { muted: true };
  assert.equal(shows(entry(1), muted, false), false);
  assert.equal(shows(critical(1), muted, false), false);
  assert.equal(shows(entry(1), undefined, false), true);
  assert.equal(shows(entry(1), undefined, true), false);
  assert.equal(shows(critical(1), undefined, true), true);
});

test('m mutes an app by its exact name, and m again leaves it with no rule', () => {
  const once = toggle({}, 'slack', 'muted');
  assert.deepEqual(once, { slack: { muted: true } });
  assert.equal(once.Slack, undefined);
  assert.deepEqual(toggle(once, 'slack', 'muted'), {});
});

test('a group heading ends with the rule of its app, and no rule adds nothing', () => {
  assert.equal(ruleText({ muted: true }), ' · muted');
  assert.equal(ruleText(undefined), '');
});

test('an app let through Do Not Disturb shows under it, and a muted one still does not', () => {
  assert.equal(shows(entry(1), { dnd: true }, true), true);
  assert.equal(shows(entry(1), { dnd: true }, false), true);
  assert.equal(shows(entry(1), { muted: true, dnd: true }, true), false);
});

test('i lets an app through Do Not Disturb beside its mute, and the heading names both', () => {
  const both = toggle(toggle({}, 'T', 'muted'), 'T', 'dnd');
  assert.deepEqual(both, { T: { muted: true, dnd: true } });
  assert.equal(ruleText(both.T), ' · muted · through DND');
  assert.equal(ruleText({ dnd: true }), ' · through DND');
  assert.deepEqual(toggle(both, 'T', 'muted'), { T: { dnd: true } });
});

test('s cycles how long an app stays: 3 s, 10 s, until dismissed, then its own time again', () => {
  const stays = [];
  let rules = {};
  for (let i = 0; i < 4; i++) {
    rules = cycleStay(rules, 'T');
    stays.push(ruleText(rules.T));
  }
  assert.deepEqual(stays, [' · stays 3 s', ' · stays 10 s', ' · stays until dismissed', '']);
  assert.deepEqual(rules, {});
});

test('a rule that sets all three reads mute, Do Not Disturb, then the stay', () => {
  assert.equal(ruleText({ muted: true, dnd: true, stays: 10000 }), ' · muted · through DND · stays 10 s');
});

test('the stay of a rule beats the timeout the app sent, on a critical too', () => {
  assert.equal(holdMs(Object.assign(entry(1), { timeout: 2000 }), { stays: 10000 }), 10000);
  assert.equal(holdMs(Object.assign(entry(1), { timeout: 0 }), { stays: 3000 }), 3000);
  assert.equal(holdMs(Object.assign(entry(1), { timeout: 2000 }), { stays: 0 }), 0);
  assert.equal(holdMs(critical(1), { stays: 3000 }), 3000);
  assert.equal(holdMs(Object.assign(entry(1), { timeout: 2000 }), { muted: true }), 2000);
});

test('a critical whose app stays 3 s is not set aside, and one whose app stays until dismissed is', () => {
  assert.deepEqual(setAside([], critical(1), 'k2', { 'notify-send': { stays: 3000 } }), []);
  assert.deepEqual(setAside([], Object.assign(critical(1), { timeout: 3000 }), 'k2', { 'notify-send': { stays: 0 } }).map((e) => e.key), ['k1']);
});

test('a paused hold resumes by the stay of its app', () => {
  assert.equal(resumeMs(Object.assign(entry(1), { timeout: 0 }), 400, { stays: 3000 }), 1500);
  assert.equal(resumeMs(Object.assign(entry(1), { timeout: 2000 }), 400, { stays: 0 }), 0);
});

// Any sender can name itself after a member every object inherits.
const forged = ['__proto__', 'constructor', 'toString', 'hasOwnProperty'];

test('an app named after an inherited member gets its own group', () => {
  const groups = group(forged.map((app, i) => entry(i, app)).concat([entry(9, 'mail')]));
  assert.deepEqual(groups.map((g) => [g.app, g.entries.length]), [['mail', 1]].concat(forged.slice().reverse().map((a) => [a, 1])));
});

test('an app named after an inherited member has no rule until it gets one, and its rule stays its own', () => {
  for (const app of forged) {
    assert.equal(ruleOf({}, app), undefined);
    const rules = toggle({ mail: { dnd: true } }, app, 'muted');
    assert.deepEqual(ruleOf(rules, app), { muted: true });
    assert.deepEqual(ruleOf(rules, 'mail'), { dnd: true });
    assert.equal(ruleOf(rules, 'muted'), undefined);
    assert.deepEqual(ruleOf(cycleStay(rules, app), app), { muted: true, stays: 3000 });
    assert.deepEqual(ruleOf(parseStore(storeText({ dnd: false, rules, history: [] })).rules, app), { muted: true });
    assert.deepEqual(Object.keys(toggle(rules, app, 'muted')), ['mail']);
  }
});

test('an entry from an app named after an inherited member holds by its own timeout', () => {
  assert.deepEqual(setAside([], Object.assign(critical(1), { app: 'constructor' }), 'k2').map((e) => e.key), ['k1']);
});

test('the chips are the first three actions, numbered from 1, never default or settings', () => {
  const a = (identifier, text) => ({ identifier, text });
  assert.deepEqual(chipsOf([a('default', 'Open'), a('yes', 'Yes'), a('settings', 'Settings'), a('no', 'No'), a('later', 'Later'), a('never', 'Never')]), [
    { key: '1', identifier: 'yes', text: 'Yes' },
    { key: '2', identifier: 'no', text: 'No' },
    { key: '3', identifier: 'later', text: 'Later' },
  ]);
  assert.deepEqual(chipsOf([a('default', 'Open')]), []);
  assert.deepEqual(chipsOf(undefined), []);
});

test("an action raises the app's most recently focused window, by desktop entry or app name against the app id", () => {
  const w = (id, app_id, secs, nanos = 0) => ({ id, app_id, focus_timestamp: { secs, nanos } });
  const windows = [w(1, 'foot', 100), w(2, 'chromium-browser', 300), w(3, 'foot', 200, 5), w(4, 'foot', 200, 1), { id: 5, app_id: 'foot', focus_timestamp: null }];
  assert.equal(raiseTarget(windows, { app: 'foot', desktopEntry: '' }), 3);
  assert.equal(raiseTarget(windows, { app: 'Chromium', desktopEntry: 'chromium-browser' }), 2);
  assert.equal(raiseTarget(windows, { app: 'Foot', desktopEntry: '' }), 3);
  assert.equal(raiseTarget(windows, { app: 'x', desktopEntry: 'foot.desktop' }), 3);
  assert.equal(raiseTarget(windows, { app: 'Slack', desktopEntry: 'slack' }), null);
  assert.equal(raiseTarget([{ id: 6, app_id: null, focus_timestamp: null }], { app: '', desktopEntry: '' }), null);
});
