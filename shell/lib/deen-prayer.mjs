// Deen's Prayer: a day's five prayers read from `deen prayer`, which one is next, and the words the page draws; the clock is always passed in.
import { oneLine } from './deen.mjs';
import { clockText, pad2 } from './margins.mjs';

const PRAYERS = [
  ['fajr', 'Fajr'],
  ['dhuhr', 'Dhuhr'],
  ['asr', 'Asr'],
  ['maghrib', 'Maghrib'],
  ['isha', 'Isha'],
];
const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

const minutesOf = (hhmm) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));
const clockMinutes = (now) => now.getHours() * 60 + now.getMinutes();
const utc = (key) => Date.UTC(Number(key.slice(0, 4)), Number(key.slice(5, 7)) - 1, Number(key.slice(8, 10)));

export const nameOf = (key) => PRAYERS.filter(([k]) => k === key)[0][1];

export const clock = clockText;

// DOTS_DEEN_NOW as an ISO local time such as 2026-10-23T14:32; anything else is no time.
export function parseNow(text) {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(String(text ?? ''));
  if (!m) return null;
  const [y, mo, d, h, mi] = m.slice(1).map(Number);
  const t = new Date(y, mo - 1, d, h, mi);
  return t.getFullYear() === y && t.getMonth() === mo - 1 && t.getDate() === d && t.getHours() === h && t.getMinutes() === mi ? t : null;
}

export const dayKey = (d) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;

export function shiftDay(key, by) {
  const t = new Date(utc(key) + by * 86400000);
  return `${t.getUTCFullYear()}-${pad2(t.getUTCMonth() + 1)}-${pad2(t.getUTCDate())}`;
}

export const dayDiff = (from, to) => Math.round((utc(to) - utc(from)) / 86400000);

// What stands where NEXT PRAYER does on a day that is not today.
export const dayWord = (diff) => (diff === 1 ? 'Tomorrow' : diff === -1 ? 'Yesterday' : diff > 0 ? `in ${diff} days` : `${-diff} days ago`);

// The first prayer after this minute, with the minutes left; null once Isha has passed.
export function next(times, now) {
  const here = clockMinutes(now);
  for (const [key] of PRAYERS) {
    const at = minutesOf(times[key]);
    if (at > here) return { name: key, time: times[key], left: at - here };
  }
  return null;
}

// Minutes from now to a time on the next day.
export const untilTomorrow = (hhmm, now) => 1440 - clockMinutes(now) + minutesOf(hhmm);

export const countdown = (left) => (left < 60 ? `${left} min` : `${Math.floor(left / 60)} h ${pad2(left % 60)} min`);

// The five rows; on today, a passed prayer is past and the next is marked, and Asr is Hanafi on its row either way.
export function rows(times, now, today) {
  const coming = today ? next(times, now) : null;
  return PRAYERS.map(([key, name]) => {
    const isNext = coming !== null && coming.name === key;
    return {
      name,
      time: times[key],
      past: today && minutesOf(times[key]) <= clockMinutes(now),
      next: isNext,
      tag: isNext ? (key === 'asr' ? 'next · Hanafi' : 'next') : key === 'asr' ? 'Hanafi' : '',
    };
  });
}

// Blueprint writes its lines in capitals and its date as an ISO date.
export function dateLine(key, sunrise, shout) {
  const t = new Date(utc(key));
  const day = DAYS[t.getUTCDay()];
  const line = shout ? `${day} ${key} · sunrise ${sunrise}` : `${day} ${t.getUTCDate()} ${MONTHS[t.getUTCMonth()]} ${t.getUTCFullYear()} · sunrise ${sunrise}`;
  return shout ? line.toUpperCase() : line;
}

export const methodLine = (name, cached) => `Method: ${name} · aladhan${cached ? ', cached for the month' : ''}`;

// The backend's answer with its words made fit to draw; null for an error or one with no times.
export function parsePrayer(answer) {
  if (!answer || answer.error || !answer.times) return null;
  const times = {};
  for (const key of ['fajr', 'sunrise'].concat(PRAYERS.map(([k]) => k))) {
    if (!/^\d{2}:\d{2}$/.test(String(answer.times[key]))) return null;
    times[key] = answer.times[key];
  }
  return {
    city: oneLine(answer.city),
    date: String(answer.date),
    times,
    method: oneLine(answer.method && answer.method.name),
    cached: answer.cached === true,
  };
}
