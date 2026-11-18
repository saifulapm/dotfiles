// Accounts' card from bin/dots-accounts' rows and the Claude account registry: the accounts with their limits, then balances, then usage, in the words board 8 uses.
import { line } from './voice.mjs';
import { CONTROL } from './clean.mjs';

// Labels come from a registry file and from provider names, so each is one line with no control characters, and elided.
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

// One card fits this many; the rows come from files anyone can write, and a thousand froze the shell.
const MOST = { accounts: 4, limits: 4, balances: 10, usage: 6 };

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

// A limit bar is a share from 0 to 1, in the danger tone from 0.8.
export function limitBar(share) {
  const s = clamp(share);
  return { share: s, danger: s >= 0.8 };
}

// The time left to a reset as the board writes it: "40 m", "1 h 40", "2 h", "2 d"; empty once it has passed or when there is none.
export function resetIn(iso, now) {
  const at = Date.parse(iso);
  if (!iso || Number.isNaN(at) || at <= now) return '';
  const min = Math.floor((at - now) / 60000);
  if (min < 60) return `${min} m`;
  if (min < 1440) return min % 60 ? `${Math.floor(min / 60)} h ${pad(min % 60)}` : `${min / 60} h`;
  return `${Math.floor(min / 1440)} d`;
}

// The header's words for how long ago the rows were fetched; latest is a time in ms, 0 for none.
export function updatedText(latest, now) {
  if (!latest) return '';
  const min = Math.max(0, Math.floor((now - latest) / 60000));
  if (min < 1) return 'updated just now';
  if (min < 60) return `updated ${min} min ago`;
  if (min < 1440) return `updated ${Math.floor(min / 60)} h ago`;
  return `updated ${Math.floor(min / 1440)} d ago`;
}

// A tile's figure in two parts: what leads, and the muted rest from "of".
export function splitFigure(figure) {
  const i = figure.indexOf(' of ');
  return i < 0 ? [figure, ''] : [figure.slice(0, i), figure.slice(i + 1)];
}

// A limit's name as the board labels its bar.
const limitLabel = (name) => (name === '5-hour' ? '5 h' : name === 'Weekly' ? 'Week' : name.replace(/^Weekly /, 'Week '));
const grouped = (n) => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
// A grant reads whole when it is ($10), what is left always to the cent ($7.00).
function money(v, unit, grant) {
  const usd = !unit || unit === 'USD';
  const amount = grant && Number.isInteger(v) ? String(v) : v.toFixed(2);
  return usd ? `$${amount}` : `${amount} ${clean(unit)}`;
}

// A Console grant ends on a UTC date, so it reads as that date alone.
function expiresText(iso) {
  const at = Date.parse(iso);
  if (!iso || Number.isNaN(at)) return '';
  const d = new Date(at);
  return `expires ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

// One drawn row: its figure, a bar's fraction (null for none), the warning from 80% used, and a note for a stale or failed value.
function figureOf(r, now) {
  const placeholder = !num(r.value);
  const out = { label: clean(r.label), figure: '', fraction: null, warning: false, reset: placeholder ? '' : r.metric === 'grant' ? expiresText(r.resets_at) : resetText(r.resets_at, now), note: '', error: false };
  if (placeholder) {
    out.note = reasonText(r.reason);
    out.error = true;
    return out;
  }
  if (r.state === 'stale') out.note = `as of ${timeOf(r.as_of)}`;
  if (r.kind === 'percent') {
    const pct = Math.round(r.value);
    const bar = limitBar(r.value / 100);
    out.percent = pct;
    out.fraction = bar.share;
    out.warning = bar.danger;
    out.figure = r.provider === 'claude' ? `${pct}% used` : `${pct}% of ${clean(r.metric)} window`;
  } else if (r.kind === 'spend') {
    // Money spent in a window, never what is left, so it draws with no bar.
    out.figure = `${money(r.value, r.unit)} ${clean(r.metric)}`;
  } else if (r.kind === 'tokens') {
    // A balance kept in tokens, not money.
    out.figure = `${grouped(r.value)} tokens`;
  } else if (r.kind === 'count') {
    out.figure = num(r.limit) ? `${grouped(r.value)} of ${grouped(r.limit)} ${clean(r.unit)}` : `${grouped(r.value)} ${clean(r.unit)}`;
    if (num(r.limit) && r.limit > 0) {
      const bar = limitBar(r.value / r.limit);
      out.fraction = bar.share;
      out.warning = bar.danger;
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

// context7Text is the state file dots context7 use writes: the id of this device's key, main when it is empty.
export function accountsView(registryText, rowsText, now, busy, context7Text) {
  const parsed = parse(rowsText, []);
  const rows = Array.isArray(parsed) ? parsed.filter((r) => r && typeof r === 'object') : [];
  const reg = accountsOf(registryText);
  const accounts = reg.list.slice(0, MOST.accounts).map((a) => {
    const own = rows.filter((r) => r.provider === 'claude' && r.account === a.id);
    // The credit rows are kept first and the limits fill what is left of the card's rows.
    const good = own.filter((r) => num(r.value));
    const credit = good.filter((r) => r.kind === 'money').slice(0, MOST.limits);
    const failed = own.find((r) => !num(r.value));
    const stale = own.find((r) => r.state === 'stale');
    let note = '';
    if (failed) note = reasonText(failed.reason);
    else if (stale) note = `stale · as of ${timeOf(stale.as_of)}` + (stale.reason === 'expired' ? ' · run cx in this account' : '');
    const limits = [...good.filter((r) => r.kind !== 'money').slice(0, MOST.limits - credit.length), ...credit].map((r) => {
      const l = figureOf(r, now);
      const name = cap(clean(r.metric));
      const left = l.percent == null ? l.figure : `${l.percent}%`;
      return Object.assign(l, { name, label: limitLabel(name), short: left, right: [left, resetIn(r.resets_at, now)].filter(Boolean).join(' · ') });
    });
    return {
      id: a.id,
      label: clean(a.label || a.id),
      plan: cap(clean(a.plan)),
      active: a.id === reg.active,
      note,
      dim: note !== '',
      limits,
      // The one line an account that is not active takes: "5 h 12% · week 30%".
      line: limits.map((l) => `${l.label.toLowerCase()} ${l.short}`).join(' · '),
    };
  });
  const others = rows.filter((r) => r.provider !== 'claude');
  const balances = others.filter((r) => r.kind === 'money' || r.kind === 'tokens').slice(0, MOST.balances).map((r) => figureOf(r, now));
  const ctx7 = String(context7Text || '').split('\n')[0].trim() || 'main';
  const keyOf = (r) => (r.provider === 'context7' && typeof r.account === 'string' ? { context7: r.account, active: r.account === ctx7 } : {});
  const usage = others.filter((r) => r.kind === 'percent' || r.kind === 'count' || r.kind === 'spend').slice(0, MOST.usage).map((r) => Object.assign(figureOf(r, now), keyOf(r)));
  const latest = rows.reduce((m, r) => Math.max(m, Date.parse(r.as_of) || 0), 0);
  return { accounts, balances, usage, latest, busy: !!busy };
}

// What the card draws, in drawing order: the accounts, then the balance and usage tiles; the cursor stops on what Enter acts on. The active Context7 key says it is this device's.
export function accountsItems(view) {
  const items = [];
  for (const a of view.accounts) items.push(Object.assign({ kind: 'account', account: a.id }, a));
  for (const [kind, list] of [['balance', view.balances], ['usage', view.usage]]) {
    for (const r of list) {
      const [main, rest] = splitFigure(r.figure);
      const name = r.context7 && r.active ? `${r.label} · this device` : r.label;
      items.push(Object.assign({ kind, account: null, name, main, rest }, r));
    }
  }
  return items.map((it) => Object.assign(it, { key: `${it.kind}:${it.label}`, stop: !!(useTarget(it) || context7Target(it)) }));
}

// The account Enter makes active: an account row that is not active already; a provider row takes none here, and a Context7 key's row goes to context7Target.
export const useTarget = (item) => (item && item.kind === 'account' && !item.active ? item.account : null);

// The Context7 key Enter makes this device's: a key row that is not the active one already.
export const context7Target = (item) => (item && item.kind === 'usage' && item.context7 && !item.active ? item.context7 : null);

// What the island says once the state file names the key.
export const context7Notice = (id) => `Context7 · ${clean(id)} is active on this device`;

// What the island says once the registry names the account; the label is the card's, already one line.
export const activeNotice = (label) => `Claude · ${label} is active for new sessions`;
