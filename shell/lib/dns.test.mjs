import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { listLook } from './voice.mjs';
import { dnsView, dnsItems, dnsLook, dnsKeys, paneOf, kidArgs, categoryArgs, allowArgs } from './dns.mjs';

process.env.TZ = 'Asia/Dhaka';

// 2026-10-22 15:12 in Dhaka.
const NOW = Date.parse('2026-10-22T09:12:00Z');
const S = NOW / 1000;
const cats = (y, s, a, g) => ({ youtube: y, social: s, adult: a, gambling: g });
const device = (o) => Object.assign({ path: 'carried', kid: false, categories: cats(false, false, false, false), open_until: null, allow: [], last_block: null, blocks: [], ip: null, mac: null }, o);
const router = (n, name, kid, last) =>
  device({ key: `router:02:00:00:00:00:0${n}`, name, path: 'router', kid, categories: cats(kid, kid, kid, kid), allow: kid ? ['wikipedia.org'] : [], last_block: last, blocks: last ? [{ domain: 'tiktok.com', at: last }] : [], ip: `192.168.0.10${n}`, mac: `02:00:00:00:00:0${n}` });
const sample = (over) => ({
  as_of: S,
  carried: { ok: true, error: null },
  router: { ok: true, as_of: S, error: null },
  devices: [
    device({ key: 'carried:dev00iphone', name: "Saiful's iPhone" }),
    device({
      key: 'carried:dev00ipad',
      name: 'iPad',
      kid: true,
      categories: cats(true, true, true, false),
      allow: ['khanacademy.org', 'wikipedia.org'],
      last_block: S - 120,
      blocks: [{ domain: 'youtube.com', at: S - 120 }, { domain: 'i.ytimg.com', at: S - 125 }, { domain: 'tiktok.com', at: S - 3700 }],
    }),
    device({ key: 'carried:dev00wife', name: "Wife's iPhone" }),
    router(1, 'macbook', false, null),
    router(2, 'nuc', false, null),
    router(3, 'mini', false, null),
    router(4, "Sister's phone", true, S - 41 * 60),
    router(5, 'Living-room TV', true, S - 3600),
  ].map((d) => Object.assign(d, (over || {})[d.key] || {})),
});
const view = (over) => dnsView(JSON.stringify(sample(over)), NOW);
const at = (v, key) => v.carried.concat(v.router).find((d) => d.key === key);

test('the board sample reads as 3 carried and 5 router devices, with KID or OPEN and the age of each last block', () => {
  const v = view();
  assert.deepEqual(v.carried.map((d) => [d.name, d.badge, d.age]), [["Saiful's iPhone", 'OPEN', '—'], ['iPad', 'KID', '2m'], ["Wife's iPhone", 'OPEN', '—']]);
  assert.deepEqual(v.router.map((d) => [d.name, d.badge, d.age]), [['macbook', 'OPEN', '—'], ['nuc', 'OPEN', '—'], ['mini', 'OPEN', '—'], ["Sister's phone", 'KID', '41m'], ['Living-room TV', 'KID', '1h']]);
  assert.equal(v.footer, 'as of 15:12');
});

test('a block under a minute old reads now, and one days old reads in days', () => {
  const v = view({ 'carried:dev00iphone': { last_block: S - 20 }, 'carried:dev00wife': { last_block: S - 3 * 86400 } });
  assert.deepEqual([at(v, 'carried:dev00iphone').age, at(v, 'carried:dev00wife').age], ['now', '3d']);
});

test('the cursor stops on every device across both groups, never on a group label or the add row', () => {
  const items = dnsItems(view());
  assert.deepEqual(items.map((i) => i.kind), ['group', 'device', 'device', 'device', 'group', 'device', 'device', 'device', 'device', 'device', 'add']);
  assert.deepEqual(items.filter((i) => i.stop).map((i) => i.key), [
    'carried:dev00iphone', 'carried:dev00ipad', 'carried:dev00wife',
    'router:02:00:00:00:00:01', 'router:02:00:00:00:00:02', 'router:02:00:00:00:00:03', 'router:02:00:00:00:00:04', 'router:02:00:00:00:00:05',
  ]);
  assert.deepEqual(items.filter((i) => i.kind === 'group').map((i) => [i.label, i.count]), [['Carried profile', 3], ['Home router', 5]]);
});

const theme = (name) => parseToml(readFileSync(new URL(`../../themes/${name}/theme.toml`, import.meta.url), 'utf8'));

test("each theme labels the groups in its voice: Paper's and Blueprint's caps, Artboard's plain words", () => {
  const groups = dnsItems(view()).filter((i) => i.kind === 'group');
  const label = (name) => groups.map((g) => dnsLook(theme(name)).group(g));
  assert.deepEqual(label('paper'), [{ text: 'CARRIED PROFILE · 3', right: 'LAST BLOCK' }, { text: 'HOME ROUTER · 5', right: 'LAST BLOCK' }]);
  assert.deepEqual(label('artboard'), [{ text: 'Carried profile · 3', right: 'Last block' }, { text: 'Home router · 5', right: 'Last block' }]);
  assert.deepEqual(label('blueprint'), [{ text: 'CARRIED PROFILE · 3', right: 'LAST BLOCK' }, { text: 'HOME ROUTER · 5', right: 'LAST BLOCK' }]);
});

test("each theme's key strip is the board's", () => {
  const strip = (n) => dnsKeys(listLook(theme(n))).map((k) => `${k.key} ${k.word}`.trim());
  assert.deepEqual(strip('artboard'), ['space kid mode', '1-4 categories', 'o open 30m', 'O 2h', 'a allow', 'n add device', 'esc']);
  assert.deepEqual(strip('paper'), ['SPACE KID MODE', '1-4 CATEGORIES', 'O OPEN 30M', 'O 2H', 'A ALLOW', 'N ADD DEVICE', 'ESC']);
});

test("a carried KID device's pane: its path, KID, the four categories with Gambling off, its allow list and recent blocks", () => {
  assert.deepEqual(paneOf(at(view(), 'carried:dev00ipad')), {
    name: 'iPad',
    path: 'Carried profile · uBlockDNS',
    badge: 'KID',
    categories: [
      { n: 1, key: 'youtube', label: 'YouTube', value: 'ON' },
      { n: 2, key: 'social', label: 'Social', value: 'ON' },
      { n: 3, key: 'adult', label: 'Adult', value: 'ON' },
      { n: 4, key: 'gambling', label: 'Gambling', value: 'OFF' },
    ],
    allow: ['khanacademy.org', 'wikipedia.org'],
    blocks: [{ domain: 'youtube.com', age: '2m' }, { domain: 'i.ytimg.com', age: '2m' }, { domain: 'tiktok.com', age: '1h' }],
    hint: '',
  });
});

test("an OPEN device's pane shows its recent blocks and that space turns Kid mode on, and nothing else", () => {
  const v = view({ 'carried:dev00wife': { allow: ['khanacademy.org'], blocks: [{ domain: 'reddit.com', at: S - 600 }] } });
  assert.deepEqual(paneOf(at(v, 'carried:dev00wife')), {
    name: "Wife's iPhone",
    path: 'Carried profile · uBlockDNS',
    badge: 'OPEN',
    categories: [],
    allow: [],
    blocks: [{ domain: 'reddit.com', age: '10m' }],
    hint: 'space turns Kid mode on',
  });
});

test("a router KID device's pane reads Home router with all four categories on with Kid and the shared allow list", () => {
  const pane = paneOf(at(view(), 'router:02:00:00:00:00:04'));
  assert.deepEqual([pane.name, pane.path, pane.badge, pane.hint], ["Sister's phone", 'Home router', 'KID', '']);
  assert.deepEqual(pane.categories.map((c) => `${c.n} ${c.label} ${c.value}`), ['1 YouTube ON', '2 Social ON', '3 Adult ON', '4 Gambling ON']);
  assert.deepEqual(pane.allow, ['wikipedia.org']);
});

test('space turns Kid off on a KID device and on on an OPEN one', () => {
  const v = view();
  assert.deepEqual(kidArgs(at(v, 'carried:dev00ipad')), ['kid', 'carried:dev00ipad', 'off']);
  assert.deepEqual(kidArgs(at(v, 'carried:dev00wife')), ['kid', 'carried:dev00wife', 'on']);
  assert.deepEqual(kidArgs(at(v, 'router:02:00:00:00:00:04')), ['kid', 'router:02:00:00:00:00:04', 'off']);
});

test('1-4 flip a category on a carried KID device only', () => {
  const v = view();
  const ipad = at(v, 'carried:dev00ipad');
  assert.deepEqual([1, 4].map((n) => categoryArgs(ipad, n)), [['category', 'carried:dev00ipad', 'youtube', 'off'], ['category', 'carried:dev00ipad', 'gambling', 'on']]);
  assert.equal(categoryArgs(at(v, 'carried:dev00wife'), 1), null);
  assert.equal(categoryArgs(at(v, 'router:02:00:00:00:00:04'), 2), null);
  assert.equal(categoryArgs(ipad, 5), null);
});

test('a adds a typed domain, one-lined, on a KID device only, and an empty one adds nothing', () => {
  const v = view();
  assert.deepEqual(allowArgs(at(v, 'router:02:00:00:00:00:05'), ' khanacademy.org\n'), ['allow', 'router:02:00:00:00:00:05', 'khanacademy.org']);
  assert.equal(allowArgs(at(v, 'router:02:00:00:00:00:05'), ' \n'), null);
  assert.equal(allowArgs(at(v, 'carried:dev00wife'), 'khanacademy.org'), null);
});

test('forged names and domains are one-lined and stripped of controls and bidi marks, and an empty name reads as its key', () => {
  const long = 'W'.repeat(200);
  const v = view({
    'carried:dev00iphone': { name: 'two\nlines' },
    'carried:dev00ipad': { name: 'evil‮gnp.exe', blocks: [{ domain: 'bad\u001b[31m.com', at: S - 120 }], allow: ['a⁦b.org'] },
    'carried:dev00wife': { name: '' },
    'router:02:00:00:00:00:01': { name: 'esc\u001b[2Jape' },
    'router:02:00:00:00:00:02': { name: long },
    'router:02:00:00:00:00:03': { name: null },
  });
  assert.deepEqual(v.carried.concat(v.router).map((d) => d.name).slice(0, 6), ['two lines', 'evilgnp.exe', 'dev00wife', 'esc [2Jape', long, '02:00:00:00:00:03']);
  const ipad = paneOf(at(v, 'carried:dev00ipad'));
  assert.deepEqual([ipad.blocks[0].domain, ipad.allow[0]], ['bad [31m.com', 'ab.org']);
});

test('state that will not parse draws no devices and no footer', () => {
  const v = dnsView('not json', NOW);
  assert.deepEqual([v.carried, v.router, v.footer], [[], [], '']);
});
