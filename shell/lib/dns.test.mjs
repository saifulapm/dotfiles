import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { listLook } from './voice.mjs';
import { dnsView, dnsItems, dnsLook, dnsKeys, paneOf, kidArgs, categoryArgs, allowArgs, badgeText, openFraction, openArgs, leasesView, addArgs, addKeys } from './dns.mjs';

process.env.TZ = 'Asia/Dhaka';

// 2026-10-22 15:12 in Dhaka.
const NOW = Date.parse('2026-10-22T09:12:00Z');
const S = NOW / 1000;
const cats = (y, k, s, a, g) => ({ youtube: y, youtube_kids: k, social: s, adult: a, gambling: g });
const device = (o) => Object.assign({ path: 'carried', kid: false, categories: cats(false, false, false, false, false), open_until: null, allow: [], last_block: null, blocks: [], ip: null, mac: null }, o);
const router = (n, name, kid, last) =>
  device({ key: `router:02:00:00:00:00:0${n}`, name, path: 'router', kid, categories: cats(kid, kid, kid, kid, kid), allow: kid ? ['wikipedia.org'] : [], last_block: last, blocks: last ? [{ domain: 'tiktok.com', at: last }] : [], ip: `192.168.0.10${n}`, mac: `02:00:00:00:00:0${n}` });
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
      categories: cats(true, false, true, true, false),
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

test("each theme's key strip is the board's, each key as typed so o and O read apart", () => {
  const strip = (n) => dnsKeys(listLook(theme(n))).map((k) => `${k.key} ${k.word}`.trim());
  assert.deepEqual(strip('artboard'), ['space kid mode', '1-5 categories', 'o open 30m', 'O 2h', 'a allow', 'n add device', 'esc']);
  assert.deepEqual(strip('paper'), ['space KID MODE', '1-5 CATEGORIES', 'o OPEN 30M', 'O 2H', 'a ALLOW', 'n ADD DEVICE', 'esc']);
  assert.deepEqual(strip('blueprint'), ['[space] KID MODE', '[1-5] CATEGORIES', '[o] OPEN 30M', '[O] 2H', '[a] ALLOW', '[n] ADD DEVICE', '[esc]']);
});

test("a carried KID device's pane: its path, KID, the five categories with YouTube Kids and Gambling off, its allow list and recent blocks", () => {
  assert.deepEqual(paneOf(at(view(), 'carried:dev00ipad')), {
    name: 'iPad',
    path: 'Carried profile · uBlockDNS',
    badge: 'KID',
    categories: [
      { n: 1, key: 'youtube', label: 'YouTube', value: 'ON' },
      { n: 2, key: 'youtube_kids', label: 'YouTube Kids', value: 'OFF' },
      { n: 3, key: 'social', label: 'Social', value: 'ON' },
      { n: 4, key: 'adult', label: 'Adult', value: 'ON' },
      { n: 5, key: 'gambling', label: 'Gambling', value: 'OFF' },
    ],
    paused: '',
    until: '',
    shared: '',
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
    paused: '',
    until: '',
    shared: '',
    allow: [],
    blocks: [{ domain: 'reddit.com', age: '10m' }],
    hint: 'space turns Kid mode on',
  });
});

test("a router KID device's pane reads Home router with all five categories on with Kid and the shared allow list", () => {
  const pane = paneOf(at(view(), 'router:02:00:00:00:00:04'));
  assert.deepEqual([pane.name, pane.path, pane.badge, pane.hint], ["Sister's phone", 'Home router', 'KID', '']);
  assert.deepEqual(pane.categories.map((c) => `${c.n} ${c.label} ${c.value}`), ['1 YouTube ON', '2 YouTube Kids ON', '3 Social ON', '4 Adult ON', '5 Gambling ON']);
  assert.deepEqual(pane.allow, ['wikipedia.org']);
  assert.equal(pane.shared, 'shared by every home-router device');
});

test("a router allowing YouTube Kids reads it OFF on every Kid router row's pane", () => {
  const off = { categories: { youtube: true, youtube_kids: false, social: true, adult: true, gambling: true } };
  const v = view({ 'router:02:00:00:00:00:04': off, 'router:02:00:00:00:00:05': off });
  assert.deepEqual(['router:02:00:00:00:00:04', 'router:02:00:00:00:00:05'].map((k) => paneOf(at(v, k)).categories[1].value), ['OFF', 'OFF']);
});

test('space turns Kid off on a KID device and on on an OPEN one', () => {
  const v = view();
  assert.deepEqual(kidArgs(at(v, 'carried:dev00ipad')), ['kid', 'carried:dev00ipad', 'off']);
  assert.deepEqual(kidArgs(at(v, 'carried:dev00wife')), ['kid', 'carried:dev00wife', 'on']);
  assert.deepEqual(kidArgs(at(v, 'router:02:00:00:00:00:04')), ['kid', 'router:02:00:00:00:00:04', 'off']);
});

test('1-5 flip a category on a carried KID device; on a Kid router row only 2 does, the one YouTube Kids setting every router device shares', () => {
  const v = view();
  const ipad = at(v, 'carried:dev00ipad');
  assert.deepEqual([1, 2, 5].map((n) => categoryArgs(ipad, n)), [
    ['category', 'carried:dev00ipad', 'youtube', 'off'],
    ['category', 'carried:dev00ipad', 'youtube_kids', 'on'],
    ['category', 'carried:dev00ipad', 'gambling', 'on'],
  ]);
  assert.equal(categoryArgs(at(v, 'carried:dev00wife'), 1), null);
  const sister = at(v, 'router:02:00:00:00:00:04');
  assert.deepEqual([1, 2, 3, 4, 5].map((n) => categoryArgs(sister, n)), [null, ['category', 'router:02:00:00:00:00:04', 'youtube_kids', 'off'], null, null, null]);
  assert.equal(categoryArgs(at(v, 'router:02:00:00:00:00:01'), 2), null);
  assert.equal(categoryArgs(at(dnsView(JSON.stringify(down()), NOW), 'router:02:00:00:00:00:04'), 2), null);
  assert.equal(paneOf(ipad).shared, '');
  assert.equal(categoryArgs(ipad, 6), null);
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

// A timed open: the iPad paused until 15:36, 24:10 left of 30 minutes, as DnsOpen draws it.
const opened = (over) => view(Object.assign({ 'carried:dev00ipad': { kid: false, open_until: S + 24 * 60 + 10 } }, over));

test('a timed open reads open · mm:ss left in its badge and counts down from the clock', () => {
  const ipad = at(opened(), 'carried:dev00ipad');
  assert.deepEqual([badgeText(ipad, NOW), badgeText(ipad, NOW + 70e3), badgeText(ipad, NOW + 3600e3)], ['open · 24:10 left', 'open · 23:00 left', 'open · 00:00 left']);
  assert.equal(badgeText(at(opened(), 'carried:dev00wife'), NOW), 'OPEN');
  assert.equal(badgeText(at(opened(), 'router:02:00:00:00:00:04'), NOW), 'KID');
  const twoHours = at(opened({ 'carried:dev00ipad': { kid: false, open_until: S + 7200 } }), 'carried:dev00ipad');
  assert.equal(badgeText(twoHours, NOW), 'open · 120:00 left');
});

test("a timed open's pane: Kid paused until HH:MM, its categories paused, the open's end and bar, its allow list and blocks", () => {
  const ipad = at(opened(), 'carried:dev00ipad');
  const pane = paneOf(ipad);
  assert.equal(pane.path, 'Carried profile · Kid mode paused until 15:36');
  assert.equal(pane.badge, 'OPEN');
  assert.deepEqual(pane.categories.map((c) => `${c.n} ${c.label} ${c.value}`), ['1 YouTube paused', '2 YouTube Kids paused', '3 Social paused', '4 Adult paused', '5 Gambling paused']);
  assert.equal(pane.paused, 'paused while open');
  assert.equal(pane.until, 'Open until 15:36');
  assert.deepEqual(pane.allow, ['khanacademy.org', 'wikipedia.org']);
  assert.equal(pane.hint, '');
  // 24:10 of the 30 minutes is about 81%; with more than 30 minutes left the bar is of 2 hours.
  assert.equal(Math.round(openFraction(ipad, NOW) * 100), 81);
  assert.equal(openFraction(ipad, NOW + 3600e3), 0);
  const twoHours = at(opened({ 'carried:dev00ipad': { kid: false, open_until: S + 3600 } }), 'carried:dev00ipad');
  assert.equal(openFraction(twoHours, NOW), 0.5);
  assert.deepEqual([paneOf(at(view(), 'carried:dev00ipad')).until, paneOf(at(view(), 'carried:dev00ipad')).paused], ['', '']);
});

test('o and O open a KID device for 30m and 2h and restart a timed one, but not an OPEN one; space ends a timed open', () => {
  const v = opened();
  assert.deepEqual(openArgs(at(view(), 'carried:dev00ipad'), '30m'), ['open', 'carried:dev00ipad', '30m']);
  assert.deepEqual(openArgs(at(v, 'carried:dev00ipad'), '2h'), ['open', 'carried:dev00ipad', '2h']);
  assert.deepEqual(openArgs(at(v, 'router:02:00:00:00:00:05'), '30m'), ['open', 'router:02:00:00:00:00:05', '30m']);
  assert.equal(openArgs(at(v, 'carried:dev00wife'), '30m'), null);
  assert.deepEqual(kidArgs(at(v, 'carried:dev00ipad')), ['kid', 'carried:dev00ipad', 'on']);
  assert.equal(categoryArgs(at(v, 'carried:dev00ipad'), 1), null);
  assert.deepEqual(allowArgs(at(v, 'carried:dev00ipad'), 'x.org'), ['allow', 'carried:dev00ipad', 'x.org']);
});

const down = (o) => Object.assign(sample(o), { router: { ok: false, as_of: S - 14 * 60, error: 'unreachable' } });

test('an unreachable router dims its rows, says since when under its label, and the footer gives both ages', () => {
  const v = dnsView(JSON.stringify(down()), NOW);
  assert.deepEqual([v.carried.map((d) => d.dim), v.router.map((d) => d.dim)], [[false, false, false], [true, true, true, true, true]]);
  assert.deepEqual(v.router.map((d) => d.badge), ['OPEN', 'OPEN', 'OPEN', 'KID', 'KID']);
  assert.equal(v.footer, 'profiles as of 15:12 · router as of 14:58');
  const groups = dnsItems(v).filter((i) => i.kind === 'group');
  assert.deepEqual(groups.map((g) => g.line), ['', 'router unreachable · as of 14:58']);
  assert.deepEqual(dnsItems(view()).filter((i) => i.kind === 'group').map((g) => g.line), ['', '']);
});

test('while the router is unreachable a router row takes no write, and a carried row still does', () => {
  const v = dnsView(JSON.stringify(down()), NOW);
  const tv = at(v, 'router:02:00:00:00:00:05');
  assert.deepEqual([kidArgs(tv), openArgs(tv, '30m'), allowArgs(tv, 'x.org')], [null, null, null]);
  assert.deepEqual(kidArgs(at(v, 'carried:dev00ipad')), ['kid', 'carried:dev00ipad', 'off']);
});

test('each theme draws the unreachable line in its error voice, and the heading in its own', () => {
  const line = 'router unreachable · as of 14:58';
  const looks = ['paper', 'artboard', 'blueprint'].map((n) => dnsLook(theme(n)));
  assert.deepEqual(looks.map((l) => l.errorText(line)), [line, line, '✕ ROUTER UNREACHABLE · AS OF 14:58']);
  assert.deepEqual(looks.map((l) => l.heading(true)), ['DNS SHIELD › ADD DEVICE', 'DNS Shield › Add device', 'DNS SHIELD // ADD DEVICE']);
  assert.deepEqual(looks.map((l) => l.heading(false)), ['DNS SHIELD', 'DNS Shield', 'DNS SHIELD // DEVICES']);
});

const leases = [
  { mac: '02:00:00:00:00:41', ip: '192.168.0.143', hostname: 'Galaxy-A54' },
  { mac: '02:00:00:00:00:42', ip: '192.168.0.151', hostname: '' },
  { mac: '02:00:00:00:00:43', ip: '192.168.0.160', hostname: 'Chrome\ncast‮\u001b' },
];

test('the leases read as hostname or unnamed with their address, one-lined, and their count in each voice', () => {
  const l = leasesView(JSON.stringify(leases));
  assert.deepEqual(l.map((x) => [x.mac, x.name, x.ip, x.field]), [
    ['02:00:00:00:00:41', 'Galaxy-A54', '192.168.0.143', 'Galaxy-A54'],
    ['02:00:00:00:00:42', 'unnamed', '192.168.0.151', ''],
    ['02:00:00:00:00:43', 'Chrome cast', '192.168.0.160', 'Chrome cast'],
  ]);
  assert.deepEqual(leasesView('nope'), []);
  assert.deepEqual(['paper', 'artboard'].map((n) => dnsLook(theme(n)).leasesHead(3)), [{ text: 'ON THE NETWORK NOW · 3', right: 'IP' }, { text: 'On the network now · 3', right: 'IP' }]);
});

test('Enter adds the lease under the typed name, one-lined, and an empty name adds nothing', () => {
  const [galaxy] = leasesView(JSON.stringify(leases));
  assert.deepEqual(addArgs(galaxy, "Sister's phone"), ['add', '02:00:00:00:00:41', "Sister's phone"]);
  assert.deepEqual(addArgs(galaxy, 'two\nlines‮'), ['add', '02:00:00:00:00:41', 'two lines']);
  assert.equal(addArgs(galaxy, ' \n'), null);
  assert.equal(addArgs(undefined, 'x'), null);
});

test("the add list's key strip is the board's", () => {
  assert.deepEqual(addKeys(listLook(theme('artboard'))).map((k) => `${k.key} ${k.word}`.trim()), ['↵ add in kid mode', 'tab name', 'j/k lease', 'esc back']);
  assert.deepEqual(addKeys(listLook(theme('paper'))).map((k) => `${k.key} ${k.word}`.trim()), ['↵ ADD IN KID MODE', 'tab NAME', 'j/k LEASE', 'esc BACK']);
});
