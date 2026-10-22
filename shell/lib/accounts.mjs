// Accounts' card from bin/dots-accounts' rows and the Claude account registry: one group of accounts with their limits, then balances, then usage, in the words the boards use.
import { line } from './voice.mjs';

// Labels come from a registry file and from provider names, so each is one line with no control characters, and elided.
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const clean = (s) => {
  const t = line(String(s == null ? '' : s).replace(CONTROL, ' '));
  return t.length > 40 ? t.slice(0, 39) + '…' : t;
};
const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : '');

// The collector names a failure; the card says it in its own words, never a response's.
const REASONS = {
  timeout: 'timed out',
  network: 'no network',
  'rate-limited': 'rate limited',
  expired: 'run cx in this account',
  forbidden: "key can't read billing",
  locked: 'pass is locked',
  'no-key': 'no key',
  shape: "can't read",
  'no-home': 'home missing',
};
const reasonText = (r) => REASONS[r] || "can't read";

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const pad = (n) => String(n).padStart(2, '0');
const hhmm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const timeOf = (iso) => {
  const at = Date.parse(iso);
  return Number.isNaN(at) ? '' : hhmm(new Date(at));
};

// A reset later today reads as its time, one within the week with its day, and a later one as its date.
function resetText(iso, now) {
  const at = Date.parse(iso);
  if (!iso || Number.isNaN(at)) return '';
  const d = new Date(at);
  if (d.toDateString() === new Date(now).toDateString()) return `resets ${hhmm(d)}`;
  if (at - now < 7 * 86400000) return `resets ${DAYS[d.getDay()]} ${hhmm(d)}`;
  return `resets ${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

const num = (v) => typeof v === 'number' && Number.isFinite(v);
const clamp = (f) => Math.min(1, Math.max(0, f));
const grouped = (n) => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
// A grant reads whole when it is ($10), what is left always to the cent ($7.00).
function money(v, unit, grant) {
  const usd = !unit || unit === 'USD';
  const amount = grant && Number.isInteger(v) ? String(v) : v.toFixed(2);
  return usd ? `$${amount}` : `${amount} ${clean(unit)}`;
}

// One drawn row: its figure, a bar's fraction (null for none), the warning from 80% used, and a note for a stale or failed value.
function figureOf(r, now) {
  const placeholder = !num(r.value);
  const out = { label: clean(r.label), figure: '', fraction: null, warning: false, reset: placeholder ? '' : resetText(r.resets_at, now), note: '', error: false };
  if (placeholder) {
    out.note = reasonText(r.reason);
    out.error = true;
    return out;
  }
  if (r.state === 'stale') out.note = `as of ${timeOf(r.as_of)}`;
  if (r.kind === 'percent') {
    const pct = Math.round(r.value);
    out.fraction = clamp(r.value / 100);
    out.warning = r.value >= 80;
    out.figure = r.provider === 'claude' ? `${pct}% used` : `${pct}% of ${clean(r.metric)} window`;
  } else if (r.kind === 'count') {
    out.figure = num(r.limit) ? `${grouped(r.value)} of ${grouped(r.limit)} ${clean(r.unit)}` : `${grouped(r.value)} ${clean(r.unit)}`;
    if (num(r.limit) && r.limit > 0) {
      out.fraction = clamp(r.value / r.limit);
      out.warning = r.value / r.limit >= 0.8;
    }
  } else {
    // A money value is what is left; with a grant it reads "of" the grant, and its bar is the credit left.
    out.figure = money(r.value, r.unit) + (num(r.limit) ? ` of ${money(r.limit, r.unit, true)}` : '');
    if (num(r.limit) && r.limit > 0) out.fraction = clamp(r.value / r.limit);
  }
  return out;
}

function parse(text, fallback) {
  try {
    return JSON.parse(text);
  } catch (e) {
    return fallback;
  }
}

// No registry, or one that will not read, is the one account Claude Code always has.
function accountsOf(registryText) {
  const reg = parse(registryText, null);
  const list = reg && Array.isArray(reg.accounts) ? reg.accounts.filter((a) => a && typeof a.id === 'string') : [];
  if (!list.length) return { active: 'main', list: [{ id: 'main', label: 'main', plan: '' }] };
  return { active: reg.active, list };
}

export function accountsView(registryText, rowsText, now, busy) {
  const parsed = parse(rowsText, []);
  const rows = Array.isArray(parsed) ? parsed.filter((r) => r && typeof r === 'object') : [];
  const reg = accountsOf(registryText);
  const accounts = reg.list.map((a) => {
    const own = rows.filter((r) => r.provider === 'claude' && r.account === a.id);
    const failed = own.find((r) => !num(r.value));
    const stale = own.find((r) => r.state === 'stale');
    let note = '';
    if (failed) note = reasonText(failed.reason);
    else if (stale) note = `stale · as of ${timeOf(stale.as_of)}` + (stale.reason === 'expired' ? ' · run cx in this account' : '');
    return {
      id: a.id,
      label: clean(a.label || a.id),
      plan: cap(clean(a.plan)),
      active: a.id === reg.active,
      note,
      dim: note !== '',
      limits: own.filter((r) => num(r.value)).map((r) => Object.assign(figureOf(r, now), { name: cap(clean(r.metric)) })),
    };
  });
  const others = rows.filter((r) => r.provider !== 'claude');
  const balances = others.filter((r) => r.kind === 'money').map((r) => figureOf(r, now));
  const usage = others.filter((r) => r.kind === 'percent' || r.kind === 'count').map((r) => figureOf(r, now));
  const groups = [['Claude', accounts.length]];
  if (balances.length) groups.push(['Balances', balances.length]);
  if (usage.length) groups.push(['Usage', usage.length]);
  const latest = rows.reduce((m, r) => Math.max(m, Date.parse(r.as_of) || 0), 0);
  const footer = busy ? 'refreshing…' : latest ? `as of ${hhmm(new Date(latest))}` : '';
  return { accounts, balances, usage, groups, footer };
}

// The card's rows in drawing order; the cursor stops on account, balance and usage rows, never on a limit or a group label.
export function accountsItems(view) {
  const items = [];
  const group = (g) => items.push({ kind: 'group', label: g[0], count: g[1], stop: false, account: null });
  group(view.groups[0]);
  for (const a of view.accounts) {
    items.push({ kind: 'account', stop: true, account: a.id, label: a.label, plan: a.plan, active: a.active, note: a.note, dim: a.dim });
    for (const l of a.limits) items.push(Object.assign({ kind: 'limit', stop: false, account: a.id, dim: a.dim }, l));
  }
  for (const [kind, list, g] of [['balance', view.balances, 'Balances'], ['usage', view.usage, 'Usage']]) {
    if (!list.length) continue;
    group(view.groups.find((x) => x[0] === g));
    for (const r of list) items.push(Object.assign({ kind, stop: true, account: null, dim: false }, r));
  }
  return items;
}

export const accountsKeys = (look) => look.keys([['↵', 'make active'], ['r', 'refresh'], ['esc', '']]);

// The account Enter makes active: an account row that is not active already; a provider row takes no Enter.
export const useTarget = (item) => (item && item.kind === 'account' && !item.active ? item.account : null);

// What the island says once the registry names the account; the label is the card's, already one line.
export const activeNotice = (label) => `Claude · ${label} is active for new sessions`;

// The boards' marks that no token carries: Artboard's bar track and the dot in its ACTIVE chip.
const MARKS = { plain: { track: '#E3E6EB', dot: '#6C83FF', on: '#FFFFFF' } };
const upper = (s) => String(s).toUpperCase();
const lowerFirst = (s) => (s ? s.charAt(0).toLowerCase() + s.slice(1) : '');

// How the card's own parts read under a theme: the group labels, a limit's name, a figure, the ACTIVE mark, the bar, and the warning and stale colours.
export function accountsLook(tokens) {
  const c = tokens.color;
  const voice = tokens.type.voice;
  const plain = voice === 'plain';
  const bracket = voice === 'bracket';
  const counted = (g) => {
    const n = g[1];
    const noun = g[0] === 'Claude' ? 'ACCOUNT' : g[0] === 'Usage' && bracket ? 'WINDOW' : 'PROVIDER';
    return `${n} ${noun}${n === 1 ? '' : 'S'}`;
  };
  // Paper and Artboard draw a Claude limit as its bare percent; Blueprint dims the words after a figure.
  const figure = (item) => {
    let text = item.figure;
    if (item.kind === 'limit' && !bracket) text = text.replace(/ used$/, '');
    if (plain) return { main: item.kind === 'balance' && item.fraction !== null ? `${text} left` : text.replace(/ characters$/, ' chars'), tail: '' };
    const cut = text.indexOf(' ');
    if (!bracket || cut < 0) return { main: text, tail: '' };
    return { main: text.slice(0, cut), tail: upper(text.slice(cut + 1)).replace(/ CHARACTERS$/, ' CHARS').replace(/ WINDOW$/, '') };
  };
  return {
    voice,
    group: (g) => ({ text: plain ? g[0] : upper(g[0]), right: plain ? '' : counted(g) }),
    words: (s) => (bracket ? upper(s) : s),
    limitName: (s) => (bracket ? upper(s) : lowerFirst(s)),
    figure,
    active: plain
      ? { text: 'ACTIVE', color: MARKS.plain.on, fill: c.ink, border: 'transparent', radius: 8, dot: MARKS.plain.dot }
      : bracket
        ? { text: '[ACTIVE]', color: c.accent, fill: 'transparent', border: 'transparent', radius: 0, dot: '' }
        : { text: 'ACTIVE', color: c.ink, fill: 'transparent', border: c.ink, radius: 0, dot: '' },
    // Paper's outlined box, Artboard's rounded 6 px bar, Blueprint's row of twenty blocks.
    bar: plain ? { kind: 'round', track: MARKS.plain.track, fill: c.accent } : bracket ? { kind: 'blocks', track: c.line, fill: c.accent } : { kind: 'box', track: c.ink, fill: c.ink },
    warn: c.danger,
    dim: c.muted,
  };
}
