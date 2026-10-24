// Home's words: a continued title's episode or length and the time left, a trending title's year and rating, in each theme's voice.
import { stars } from './dekho.mjs';
import { pad2 } from './margins.mjs';

const clock = (min) => (min < 60 ? `${min} min` : `${Math.floor(min / 60)}h ${pad2(min % 60)}`);

// Blueprint's board capitals the words left, MIN LEFT, and keeps an hour's h small.
const leftText = (voice, min) => {
  const t = `${clock(min)} left`;
  return voice === 'bracket' ? t.replace(/min left$/, 'MIN LEFT').replace(/left$/, 'LEFT') : t;
};

export function continueLine(voice, item) {
  const head = item.kind === 'tv' ? `S${item.season} E${item.episode}` : item.duration ? clock(Math.round(item.duration / 60)) : '';
  if (!item.duration) return head;
  return [head, leftText(voice, Math.round(Math.max(0, item.duration - item.position) / 60))].filter((p) => p).join(' · ');
}

export function hitLine(hit) {
  return [hit.year, stars(hit.vote)].filter((p) => p).join(' · ');
}

const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// When a saved answer was saved: its age before now. Null when the answer carries no age.
export function savedAt(answer, nowMs) {
  const age = answer && answer.age_secs != null ? Number(answer.age_secs) : -1;
  return age >= 0 ? new Date(nowMs - age * 1000) : null;
}

// The boards write a day as "21 Oct" and a moment as "21 Oct 18:40", in local time with English month names.
export const savedDay = (d) => `${d.getDate()} ${months[d.getMonth()]}`;
export const savedStamp = (d) => `${savedDay(d)} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;

// The backend marks an answer it served from its saved copy as stale; no answer at all is null or an error object.
export function kindOfAnswer(answer) {
  if (!answer || typeof answer.error === 'string') return 'error';
  return answer.stale === true ? 'stale' : 'fresh';
}

// The words each board writes on Home: Paper's caps with a lower-case week, Artboard's sentence case, Blueprint's capitals and bracketed slash.
export function homeText(voice) {
  const caps = voice !== 'plain';
  const say = (s) => (caps ? s.toUpperCase() : s.charAt(0).toUpperCase() + s.slice(1));
  return {
    label: voice === 'caps' ? 'DEKHO' : 'Dekho',
    page: 'Home',
    from: voice === 'bracket' ? 'FROM THE LAUNCHER' : 'from the launcher',
    continue: say('continue watching'),
    series: say('trending series'),
    movies: say('trending movies'),
    results: say('results'),
    week: voice === 'bracket' ? 'THIS WEEK' : 'this week',
    search: 'Search films and series',
    hint: voice === 'bracket' ? '[/]' : '/',
    machine: voice === 'bracket' ? 'FROM THIS MACHINE' : 'from this machine',
    saved: (d) => (voice === 'bracket' ? `SAVED ${savedDay(d).toUpperCase()}` : `saved ${savedDay(d)}`),
    unreachable: 'TMDB is unreachable.',
    showing: (d) => (d ? `Showing saved rows from ${savedStamp(d)}.` : ''),
    retry: voice === 'bracket' ? ['[R]', 'RETRY'] : ['r', 'retry'],
    searchOff: 'Search needs TMDB',
    offlineKeys: [['r', 'retry'], ['h/j/k/l', 'move'], ['↵', 'open'], ['esc', 'close']],
    keys: [['h/j/k/l', 'move'], ['↵', 'open'], ['/', 'search'], ['f', 'filters: genre, language, person…'], ['tab', 'next row'], ['esc', 'close']],
  };
}

// The cursor's row as answers land: the first row with titles until a key has moved it, then where it was while that row still has titles.
export function cursorRow(names, row, moved) {
  if (names.length === 0) return row;
  return moved && names.includes(row) ? row : names[0];
}
