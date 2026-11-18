// The launcher's `r ` mode: a time then the words to be reminded of, kept in the synced store below and rung at its due second. Times are the local clock's.
import { line } from './voice.mjs';
import { CONTROL, MARK } from './clean.mjs';

export const MAX_PENDING = 50;
// What the preview row says while the file does not parse; nothing is set over it.
export const BROKEN = 'reminders.json does not parse; fix or remove it first';
// The same for this machine's file of the synced store.
export const brokenStore = (machine) => `reminders/${machine}.json does not parse; fix or remove it first`;

const MIN = 60000;
const DAY = 86400000;
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

const pad = (n) => String(n).padStart(2, '0');
const clock = (ms) => {
  const d = new Date(ms);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const midnight = (ms) => {
  const d = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
};
// Whole local days from one instant's date to another's; a DST day is 23 or 25 hours, so the count rounds.
const daysBetween = (from, to) => Math.round((midnight(to) - midnight(from)) / DAY);
const span = (ms) => {
  const m = Math.round(ms / MIN);
  const h = Math.floor(m / 60);
  return h ? `${h}h${m % 60 ? ` ${m % 60}m` : ''}` : `${m}m`;
};

// "17:30", "tomorrow 10:00" or "Sat 10:00": when a pending reminder rings, seen from now.
export function whenText(due, now) {
  const days = daysBetween(now, due);
  if (days === 0) return clock(due);
  if (days === 1) return `tomorrow ${clock(due)}`;
  return `${WEEKDAYS[new Date(due).getDay()]} ${clock(due)}`;
}

// C0, DEL and C1 controls, and the marks that reorder what follows; a reminder's text is anyone's paste.
const oneLine = (s) => line(s.replace(CONTROL, ' ').replace(MARK, ''));
// A time a Date can hold; past about 8.64e15 ms it is Invalid Date, which draws as NaN:NaN.
const isTime = (ms) => typeof ms === 'number' && !Number.isNaN(new Date(ms).getTime());
const isReminder = (r) => r !== null && typeof r === 'object' && typeof r.id === 'string' && typeof r.text === 'string' && isTime(r.due) && isTime(r.created);

// The old reminders.json's text as its pending list, which moves into the store. Anything in it that is not a reminder makes it broken, so it is left as it is; each text is one line, as a typed one is.
export function readReminders(text) {
  let l;
  try {
    l = JSON.parse(text);
  } catch (e) {
    return { list: [], broken: true };
  }
  if (!Array.isArray(l) || !l.every(isReminder)) return { list: [], broken: true };
  return { list: l.map((r) => Object.assign({}, r, { text: oneLine(r.text) })), broken: false };
}

// The query after `r `: "20m tea", "1h30m tea" or "17:30 call". Null while it has no time or no text yet; {error} for a time no clock has.
export function parseReminder(q, now) {
  const m = /^\s*(\S+)\s+([\s\S]*\S)/.exec(q);
  if (!m) return null;
  const text = oneLine(m[2]);
  if (!text) return null;
  const rel = /^(?:(\d+)h)?(?:(\d+)m)?$/.exec(m[1]);
  const at = /^(\d{1,2}):(\d{2})$/.exec(m[1]);
  let due;
  if (rel && (rel[1] || rel[2])) {
    const mins = Number(rel[1] || 0) * 60 + Number(rel[2] || 0);
    if (mins <= 0) return { error: `Cannot set ${m[1]}: it is not in the future` };
    due = now + mins * MIN;
    // A due no Date can hold would make the next read take the whole file as broken.
    if (!isTime(due)) return { error: `Cannot set ${m[1]}: it is too far ahead` };
  } else if (at) {
    const [h, min] = [Number(at[1]), Number(at[2])];
    if (h > 23 || min > 59) return { error: `Cannot set ${m[1]}: no clock shows it` };
    const d = new Date(now);
    d.setHours(h, min, 0, 0);
    if (d.getTime() <= now) d.setDate(d.getDate() + 1);
    due = d.getTime();
  } else return null;
  const when = daysBetween(now, due) === 0 ? `in ${span(due - now)} · ${clock(due)}` : whenText(due, now);
  return { text, due, when };
}

// Adds a parsed reminder, keeping the list soonest first; the 51st is refused with the list unchanged.
export function addReminder(list, parsed, now) {
  if (list.length >= MAX_PENDING) return { list, error: `At most ${MAX_PENDING} reminders can wait` };
  const r = { id: `${now.toString(36)}-${Math.random().toString(36).slice(2, 8)}`, text: parsed.text, due: parsed.due, created: now };
  return { list: list.concat([r]).sort((a, b) => a.due - b.due), error: '' };
}

// "at 14:51", "yesterday at 09:05" or "Mon at 09:05": a past instant, seen from now.
const pastAt = (ms, now) => {
  const days = daysBetween(ms, now);
  const day = days === 0 ? '' : days === 1 ? 'yesterday ' : `${WEEKDAYS[new Date(ms).getDay()]} `;
  return `${day}at ${clock(ms)}`;
};

// The notification a rung reminder raises.
export function firedText(r, now) {
  return { summary: `Reminder · ${r.text}`, body: `set ${pastAt(r.created, now)}` };
}

// The same, for one rung without a pull, so the reader knows another machine may have rung it already.
export function lateText(r, now) {
  return { summary: `Reminder · ${r.text}`, body: `rang late · due ${pastAt(r.due, now)} · set ${pastAt(r.created, now)}` };
}

// Due under a minute ago rings at once; due longer ago, the machine was off or asleep, and it waits for a reminders round, as another machine may have rung it.
export function dueSplit(list, now) {
  const due = list.filter((r) => r.due <= now);
  return { fresh: due.filter((r) => now - r.due < MIN), stale: due.filter((r) => now - r.due >= MIN) };
}

// A round pulled the other machines' files when dots sync exits 0, or 5, which still merged what parsed; with no Dropbox remote it exits 0 having pulled nothing.
export const roundPulled = (code, out) => (code === 0 || code === 5) && !/^dots sync: skipped/m.test(out);

// The launcher's rows in `r ` mode: the reminder the query would set (or why it cannot), then the pending ones, the first under the pending head; broken is why nothing can be set, or ''.
export function reminderRows(q, now, list, broken) {
  const parsed = parseReminder(q, now);
  const error = parsed && (parsed.error || broken || (list.length >= MAX_PENDING ? `At most ${MAX_PENDING} reminders can wait` : ''));
  const top = !parsed ? [] : error ? [{ title: error, detail: '' }] : [{ title: parsed.text, detail: parsed.when, remind: { text: parsed.text, due: parsed.due } }];
  return top.concat(list.map((r, i) => ({ title: r.text, detail: whenText(r.due, now), reminderId: r.id, head: i === 0 })));
}

// The synced store, reminders/<machine>.json in the data dir: every reminder ever set, each {id, text, due, created, ended, stamps}, where ended is null while it waits, then "rung" or "removed", and stays as a marker so a merge never brings it back.
export const emptyStore = () => ({ version: 1, reminders: [] });

const FIELDS = ['text', 'due', 'ended'];
const ENDS = [null, 'rung', 'removed'];
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const num = (v, fallback) => (typeof v === 'number' ? v : fallback);

function readRecord(r) {
  const from = isObject(r.stamps) ? r.stamps : {};
  const stamps = FIELDS.reduce((s, f) => Object.assign(s, { [f]: num(from[f], r.created) }), {});
  return { id: r.id, text: r.text, due: r.due, created: r.created, ended: r.ended ?? null, stamps };
}

const validRecord = (r) => isObject(r) && typeof r.id === 'string' && r.id !== '' && typeof r.text === 'string' && typeof r.due === 'number' && typeof r.created === 'number' && ENDS.includes(r.ended ?? null);

// A file of the wrong shape is null, so nothing saves over what it holds; a record with no text or a due no Date holds still parses, for usableOnly to count.
export function parseStore(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return null;
  }
  if (!isObject(data) || !Array.isArray(data.reminders) || !data.reminders.every(validRecord)) return null;
  return { version: 1, reminders: data.reminders.map(readRecord) };
}

const usable = (r) => oneLine(r.text) !== '' && isTime(r.due) && isTime(r.created);

// Another machine's records that could never be listed or rung are left out, and counted for the sync round to name.
export function usableOnly(store) {
  const reminders = store.reminders.filter(usable);
  return { store: Object.assign({}, store, { reminders }), dropped: store.reminders.length - reminders.length };
}

// Those still waiting, soonest first, each text one clean line.
export const pendingList = (store) =>
  store.reminders
    .filter((r) => r.ended === null && usable(r))
    .map((r) => ({ id: r.id, text: oneLine(r.text), due: r.due, created: r.created }))
    .sort((a, b) => a.due - b.due || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

const record = (r, stamp) => ({ id: r.id, text: r.text, due: r.due, created: r.created, ended: null, stamps: { text: stamp, due: stamp, ended: stamp } });

// Sets a parsed reminder as of now; with 50 already waiting, the store comes back unchanged with the reason.
export function setReminder(store, parsed, now) {
  const r = addReminder(pendingList(store), parsed, now);
  if (r.error) return { store, error: r.error };
  const added = r.list.find((x) => !store.reminders.some((y) => y.id === x.id));
  return { store: Object.assign({}, store, { reminders: store.reminders.concat([record(added, now)]) }), error: '' };
}

// Ends a waiting reminder as "rung" or "removed"; one already ended keeps how it ended.
export const endReminder = (store, id, ended, now) =>
  Object.assign({}, store, {
    reminders: store.reminders.map((r) => (r.id === id && r.ended === null ? Object.assign({}, r, { ended, stamps: Object.assign({}, r.stamps, { ended: now }) }) : r)),
  });

// The copy that set the field later wins it, and a tie goes to the larger value's text, so both machines pick the same one; an ended reminder never waits again, whatever the stamps say.
function later(a, b, f) {
  if (f === 'ended' && (a.ended === null) !== (b.ended === null)) return a.ended === null ? b : a;
  if (a.stamps[f] !== b.stamps[f]) return a.stamps[f] > b.stamps[f] ? a : b;
  return JSON.stringify(a[f]) >= JSON.stringify(b[f]) ? a : b;
}

function mergeRecord(a, b) {
  const out = { id: a.id, text: '', due: 0, created: Math.min(a.created, b.created), ended: null, stamps: {} };
  for (const f of FIELDS) {
    const from = later(a, b, f);
    out[f] = from[f];
    out.stamps[f] = from.stamps[f];
  }
  return out;
}

export function mergeStores(a, b) {
  const byId = {};
  a.reminders.concat(b.reminders).forEach((r) => {
    byId[r.id] = byId[r.id] ? mergeRecord(byId[r.id], r) : r;
  });
  return { version: 1, reminders: Object.keys(byId).sort().map((id) => byId[id]) };
}

// The old reminders.json's list joins the store with its ids, each stamped at its own created time, so a copy any machine already rang stays rung.
export const migrateOld = (store, list) => mergeStores(store, { version: 1, reminders: list.map((r) => record(r, r.created)) });
