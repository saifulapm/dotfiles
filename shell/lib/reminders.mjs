// The launcher's `r ` mode: a time then the words to be reminded of, stored as {id, text, due, created} in ~/.local/state/dots/reminders.json and rung by the minute tick. Times are the local clock's.
import { line } from './voice.mjs';

export const MAX_PENDING = 50;
// What the preview row says while the file does not parse; nothing is set over it.
export const BROKEN = 'reminders.json does not parse; fix or remove it first';

const MIN = 60000;
const DAY = 86400000;
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
// C0, DEL and C1 controls, and the marks that reorder what follows; a reminder's text is anyone's paste.
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const MARK = /[‎‏؜]/g;

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

// The query after `r `: "20m tea", "1h30m tea" or "17:30 call". Null while it has no time or no text yet; {error} for a time no clock has.
export function parseReminder(q, now) {
  const m = /^\s*(\S+)\s+([\s\S]*\S)/.exec(q);
  if (!m) return null;
  const text = line(m[2].replace(CONTROL, ' ').replace(MARK, ''));
  if (!text) return null;
  const rel = /^(?:(\d+)h)?(?:(\d+)m)?$/.exec(m[1]);
  const at = /^(\d{1,2}):(\d{2})$/.exec(m[1]);
  let due;
  if (rel && (rel[1] || rel[2])) {
    const mins = Number(rel[1] || 0) * 60 + Number(rel[2] || 0);
    if (mins <= 0) return { error: `Cannot set ${m[1]}: it is not in the future` };
    due = now + mins * MIN;
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

// Splits the list into those due by now, which ring, and the rest, which stay.
export function dueReminders(list, now) {
  return { fire: list.filter((r) => r.due <= now), keep: list.filter((r) => r.due > now) };
}

// The notification a rung reminder raises.
export function firedText(r, now) {
  const days = daysBetween(r.created, now);
  const day = days === 0 ? '' : days === 1 ? 'yesterday ' : `${WEEKDAYS[new Date(r.created).getDay()]} `;
  return { summary: `Reminder · ${r.text}`, body: `set ${day}at ${clock(r.created)}` };
}

// The launcher's rows in `r ` mode: the reminder the query would set (or why it cannot), then the pending ones, the first under the pending head.
export function reminderRows(q, now, list, broken) {
  const parsed = parseReminder(q, now);
  const error = parsed && (parsed.error || (broken ? BROKEN : list.length >= MAX_PENDING ? `At most ${MAX_PENDING} reminders can wait` : ''));
  const top = !parsed ? [] : error ? [{ title: error, detail: '' }] : [{ title: parsed.text, detail: parsed.when, remind: { text: parsed.text, due: parsed.due } }];
  return top.concat(list.map((r, i) => ({ title: r.text, detail: whenText(r.due, now), reminderId: r.id, head: i === 0 })));
}
