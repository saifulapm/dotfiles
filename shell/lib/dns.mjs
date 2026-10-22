// DNS Shield's card from `dots-dns state`: carried and router devices in two groups, KID or OPEN, and the pane for the cursor device.
import { line, listLook } from './voice.mjs';

// Names come from the uBlockDNS API and the router's reservations, which anyone on the network can set, so each is one line with no control characters; the card elides it.
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const clean = (s) => line(String(s == null ? '' : s).replace(CONTROL, ' '));

const CATEGORIES = [['youtube', 'YouTube'], ['social', 'Social'], ['adult', 'Adult'], ['gambling', 'Gambling']];
const PATHS = { carried: 'Carried profile · uBlockDNS', router: 'Home router' };

const pad = (n) => String(n).padStart(2, '0');
const hhmm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;

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

function deviceOf(d, now) {
  const key = String(d.key);
  const cats = d.categories || {};
  return {
    key,
    // A device with no name reads as its id or MAC, so its row is never blank.
    name: clean(d.name) || key.slice(key.indexOf(':') + 1),
    path: d.path,
    kid: d.kid === true,
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
  const devices = list.map((d) => deviceOf(d, now));
  return {
    carried: devices.filter((d) => d.path === 'carried'),
    router: devices.filter((d) => d.path === 'router'),
    footer: s && typeof s.as_of === 'number' ? `as of ${hhmm(new Date(s.as_of * 1000))}` : '',
  };
}

// The card's rows in drawing order; the cursor stops on devices only, so j and k cross from one group into the next.
export function dnsItems(view) {
  const items = [];
  for (const [label, list] of [['Carried profile', view.carried], ['Home router', view.router]]) {
    items.push({ kind: 'group', label, count: list.length, stop: false });
    for (const d of list) items.push(Object.assign({ kind: 'device', stop: true }, d));
  }
  items.push({ kind: 'add', stop: false });
  return items;
}

// An OPEN device shows its recent blocks and the one way back; a router device's categories come on and off with its Kid policy.
export function paneOf(d) {
  return {
    name: d.name,
    path: PATHS[d.path] || '',
    badge: d.badge,
    categories: d.kid ? d.categories.map((c) => ({ n: c.n, key: c.key, label: c.label, value: c.on ? 'ON' : 'OFF' })) : [],
    allow: d.kid ? d.allow : [],
    blocks: d.blocks,
    hint: d.kid ? '' : 'space turns Kid mode on',
  };
}

export const kidArgs = (d) => ['kid', d.key, d.kid ? 'off' : 'on'];

// Router devices carry one Kid policy, so 1-4 flip a category on a carried KID device only.
export function categoryArgs(d, n) {
  const c = d.categories[n - 1];
  if (!c || !d.kid || d.path !== 'carried') return null;
  return ['category', d.key, c.key, c.on ? 'off' : 'on'];
}

export function allowArgs(d, text) {
  const domain = clean(text);
  return d.kid && domain ? ['allow', d.key, domain] : null;
}

export const dnsKeys = (look) => look.keys([['space', 'kid mode'], ['1-4', 'categories'], ['o', 'open 30m'], ['O', '2h'], ['a', 'allow'], ['n', 'add device'], ['esc', '']]);

// A group label in the theme's voice, its count after it, and the LAST BLOCK column at the right.
export function dnsLook(tokens) {
  const look = listLook(tokens);
  return {
    group: (g) => ({ text: look.groupHead(g.label, g.count), right: look.tabText('Last block') }),
  };
}
