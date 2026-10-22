// DNS Shield's card from `dots-dns state`: carried and router devices in two groups, KID, OPEN or open for a while, the pane for the cursor device, and the router's leases to add one from.
import { line, listLook } from './voice.mjs';

// Names come from the uBlockDNS API, the router's reservations and its DHCP leases, which anyone on the network can set, so each is one line with no control characters; the card elides it.
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const clean = (s) => line(String(s == null ? '' : s).replace(CONTROL, ' '));

const CATEGORIES = [['youtube', 'YouTube'], ['youtube_kids', 'YouTube Kids'], ['social', 'Social'], ['adult', 'Adult'], ['gambling', 'Gambling']];
const PATHS = { carried: 'Carried profile · uBlockDNS', router: 'Home router' };
const PATH_NAMES = { carried: 'Carried profile', router: 'Home router' };

const pad = (n) => String(n).padStart(2, '0');
const hhmm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const timeOf = (s) => hhmm(new Date(s * 1000));

// The age of a block in whole units, floored: "2m", "41m", "1h"; none reads as a dash.
function ageOf(at, now) {
  if (typeof at !== 'number') return '—';
  const s = Math.max(0, Math.floor(now / 1000 - at));
  if (s < 60) return 'now';
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

function parse(text) {
  try {
    return JSON.parse(text);
  } catch (e) {
    return null;
  }
}

function deviceOf(d, now, routerOk) {
  const key = String(d.key);
  const cats = d.categories || {};
  return {
    key,
    // A device with no name reads as its id or MAC, so its row is never blank.
    name: clean(d.name) || key.slice(key.indexOf(':') + 1),
    path: d.path,
    kid: d.kid === true,
    openUntil: typeof d.open_until === 'number' ? d.open_until : null,
    // An unreachable router's rows keep their last values, drawn dim, and take no write.
    dim: d.path === 'router' && !routerOk,
    badge: d.kid === true ? 'KID' : 'OPEN',
    age: ageOf(d.last_block, now),
    categories: CATEGORIES.map(([k, label], i) => ({ n: i + 1, key: k, label, on: cats[k] === true })),
    allow: (Array.isArray(d.allow) ? d.allow : []).map(clean),
    blocks: (Array.isArray(d.blocks) ? d.blocks : []).filter((b) => b && typeof b === 'object').map((b) => ({ domain: clean(b.domain), age: ageOf(b.at, now) })),
  };
}

export function dnsView(text, now) {
  const s = parse(text);
  const list = s && Array.isArray(s.devices) ? s.devices.filter((d) => d && typeof d === 'object' && typeof d.key === 'string') : [];
  const router = s && s.router && typeof s.router === 'object' ? s.router : {};
  const routerOk = router.ok !== false;
  const devices = list.map((d) => deviceOf(d, now, routerOk));
  const asOf = s && typeof s.as_of === 'number' ? timeOf(s.as_of) : '';
  const routerAsOf = typeof router.as_of === 'number' ? timeOf(router.as_of) : '';
  return {
    carried: devices.filter((d) => d.path === 'carried'),
    router: devices.filter((d) => d.path === 'router'),
    routerLine: routerOk ? '' : `router unreachable · as of ${routerAsOf}`,
    footer: !asOf ? '' : routerOk ? `as of ${asOf}` : `profiles as of ${asOf} · router as of ${routerAsOf}`,
  };
}

// The card's rows in drawing order; the cursor stops on devices only, so j and k cross from one group into the next.
export function dnsItems(view) {
  const items = [];
  for (const [label, list, groupLine] of [['Carried profile', view.carried, ''], ['Home router', view.router, view.routerLine]]) {
    items.push({ kind: 'group', label, count: list.length, line: groupLine, stop: false });
    for (const d of list) items.push(Object.assign({ kind: 'device', stop: true }, d));
  }
  items.push({ kind: 'add', stop: false });
  return items;
}

const timed = (d) => d.openUntil !== null;
const secondsLeft = (d, nowMs) => Math.max(0, Math.ceil(d.openUntil - nowMs / 1000));

// A timed open counts down in minutes and seconds: "24:10", a 2-hour one from "120:00".
export function badgeText(d, nowMs) {
  if (!timed(d)) return d.badge;
  const s = secondsLeft(d, nowMs);
  return `open · ${pad(Math.floor(s / 60))}:${pad(s % 60)} left`;
}

// The bar is of the open's length: 30 minutes, or 2 hours while more than 30 minutes are left.
export function openFraction(d, nowMs) {
  const s = secondsLeft(d, nowMs);
  return s / (s > 1800 ? 7200 : 1800);
}

// An OPEN device shows its recent blocks and the one way back; a timed open shows what Kid mode will bring back, paused.
export function paneOf(d) {
  const shown = d.kid || timed(d);
  return {
    name: d.name,
    path: timed(d) ? `${PATH_NAMES[d.path] || ''} · Kid mode paused until ${timeOf(d.openUntil)}` : PATHS[d.path] || '',
    badge: d.badge,
    categories: shown ? d.categories.map((c) => ({ n: c.n, key: c.key, label: c.label, value: timed(d) ? 'paused' : c.on ? 'ON' : 'OFF' })) : [],
    paused: timed(d) ? 'paused while open' : '',
    until: timed(d) ? `Open until ${timeOf(d.openUntil)}` : '',
    // A router's YouTube Kids is one setting that every home-router device shares.
    shared: d.path === 'router' && shown ? 'shared by every home-router device' : '',
    allow: shown ? d.allow : [],
    blocks: d.blocks,
    hint: shown ? '' : 'space turns Kid mode on',
  };
}

export const kidArgs = (d) => (d.dim ? null : ['kid', d.key, d.kid ? 'off' : 'on']);

// Router devices carry one Kid policy, so 1-5 flip a category on a carried KID device; on a Kid router row only YouTube Kids flips, for every router device at once.
export function categoryArgs(d, n) {
  const c = d.categories[n - 1];
  if (!c || !d.kid || d.dim || (d.path !== 'carried' && c.key !== 'youtube_kids')) return null;
  return ['category', d.key, c.key, c.on ? 'off' : 'on'];
}

export function allowArgs(d, text) {
  const domain = clean(text);
  return (d.kid || timed(d)) && !d.dim && domain ? ['allow', d.key, domain] : null;
}

// o and O open a KID device, and restart or lengthen a timed open.
export const openArgs = (d, length) => ((d.kid || timed(d)) && !d.dim ? ['open', d.key, length] : null);

// A key chip draws its key as typed, since o and O are two keys; the words take the theme's voice and Blueprint keeps its brackets.
const keys = (look, pairs) => pairs.map(([k, w]) => ({ key: look.voice === 'bracket' ? `[${k}]` : k, word: look.tabText(w) }));

export const dnsKeys = (look) => keys(look, [['space', 'kid mode'], ['1-5', 'categories'], ['o', 'open 30m'], ['O', '2h'], ['a', 'allow'], ['n', 'add device'], ['esc', '']]);

// `dots-dns leases`: the router's leases not yet listed, each with the name the field starts from.
export function leasesView(text) {
  const list = parse(text);
  return (Array.isArray(list) ? list : [])
    .filter((l) => l && typeof l === 'object' && typeof l.mac === 'string')
    .map((l) => {
      const host = clean(l.hostname);
      return { mac: l.mac, ip: clean(l.ip), name: host || 'unnamed', field: host };
    });
}

export function addArgs(lease, text) {
  const name = clean(text);
  return lease && name ? ['add', lease.mac, name] : null;
}

// A refused write's reason: the first line dots-dns wrote to stderr, after its "dots-dns: ". It can quote a name or domain anyone on the network set, so it is cleaned like one.
export const writeError = (stderr) => clean(String(stderr).split('\n')[0].replace(/^dots-dns: /, ''));

export const addKeys = (look) => keys(look, [['↵', 'add in kid mode'], ['tab', 'name'], ['j/k', 'lease'], ['esc', 'back']]);

// A group label in the theme's voice, its count after it, a column word at the right; the heading, and a failure in the theme's error voice.
export function dnsLook(tokens) {
  const look = listLook(tokens);
  const bracket = look.voice === 'bracket';
  return {
    group: (g) => ({ text: look.groupHead(g.label, g.count), right: look.tabText('Last block') }),
    leasesHead: (n) => ({ text: look.groupHead('On the network now', n), right: look.tabText('IP') }),
    heading: (adding) => (look.label.kind === 'header' ? look.heading('DNS Shield', adding ? 'add device' : 'devices') : look.heading(adding ? 'DNS Shield › Add device' : 'DNS Shield', '')),
    errorText: (s) => (bracket ? `✕ ${s.toUpperCase()}` : s),
  };
}
