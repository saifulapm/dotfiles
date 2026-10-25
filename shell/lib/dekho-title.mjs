// The Title page's words and choices: which episode is next up, how a date and the watched count read, which crew to name, in each theme's voice.
import { stars } from './dekho.mjs';
import { resumeLine } from './dekho-home.mjs';
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const upper = (voice, s) => (voice === 'bracket' ? s.toUpperCase() : s);

// Dates stay YYYY-MM-DD strings, compared as text: a Date parsed from one is UTC midnight, a day off west of Greenwich. Only a date after today holds an episode back, so an undated one opens.
export const aired = (ep, today) => !ep.air_date || ep.air_date <= today;

// The index of the first aired episode not watched, or -1.
export function nextUp(items, today) {
  return items.findIndex((ep) => aired(ep, today) && !ep.watched);
}

// The season holding next up, else the last one; bySeason maps a season's number to its episodes.
export function startSeason(bySeason, today) {
  const numbers = Object.keys(bySeason).map(Number).sort((a, b) => a - b);
  const held = numbers.find((n) => nextUp(bySeason[n], today) >= 0);
  return held ?? numbers[numbers.length - 1];
}

export function dateText(voice, airDate, today) {
  if (!airDate) return '';
  const [, m, d] = airDate.split('-').map(Number);
  const day = `${d} ${MONTHS[m - 1]}`;
  return upper(voice, airDate <= today ? day : `airs ${day}`);
}

export function watchedText(voice, items) {
  return upper(voice, `${items.filter((ep) => ep.watched).length} of ${items.length} watched`);
}

// The backend already names a composer Composer; a screenplay is a writer's credit.
const ROLES = { Director: 'director', Writer: 'writer', Screenplay: 'writer', Composer: 'composer' };
const ORDER = ['director', 'writer', 'composer'];

export function notableCrew(crew) {
  return (crew || [])
    .filter((m) => ROLES[m.job])
    .map((m) => ({ id: m.id, name: m.name, role: ROLES[m.job] }))
    .sort((a, b) => ORDER.indexOf(a.role) - ORDER.indexOf(b.role));
}

export function chips(title) {
  const language = title.language || (title.languages || [])[0];
  return (title.genres || []).concat(language ? [language] : []);
}

const clock = (min) => (min < 60 ? `${min} min` : `${Math.floor(min / 60)}h ${String(min % 60).padStart(2, '0')}`);

export function metaText(voice, title) {
  const min = Math.round((title.runtime || 0) / 60);
  const tv = title.kind === 'tv';
  const ended = tv && title.in_production === false && title.last_air;
  const years = tv ? `${title.year} –${ended ? ` ${title.last_air.slice(0, 4)}` : ''}` : title.year;
  const length = !min ? '' : tv ? `${min} min episodes` : clock(min);
  return [years, stars(title.vote), upper(voice, length)].filter((p) => p).join(' · ');
}

export const episodeLength = (voice, secs) => (secs ? upper(voice, `${Math.round(secs / 60)} min`) : '');

export function sideText(voice, title) {
  const n = title.season_count;
  const seasons = title.kind === 'tv' && n ? `${n} season${n === 1 ? '' : 's'}` : '';
  return upper(voice, (title.genres || []).concat(seasons ? [seasons] : []).join(' · '));
}

// History's entry for a title still being watched: the same id and kind, not finished; else null.
export function watching(history, title) {
  const seen = (history || []).find((h) => h && h.id === title.id && h.kind === title.kind);
  return seen && !seen.finished ? seen : null;
}

// The title's buttons: Play always, Resume with what is left while history holds it, and Trailer when the title has one.
export function buttons(voice, seen, trailer) {
  const out = [{ id: 'play', text: upper(voice, '▶ Play') }];
  if (seen) out.push({ id: 'resume', text: upper(voice, ['▶ Resume', resumeLine(voice, seen)].filter((p) => p).join(' · ')) });
  if (trailer) out.push({ id: 'trailer', text: upper(voice, '▶ Trailer') });
  return out;
}

// The words each board writes on the Title page.
export function titleText(voice) {
  const caps = voice !== 'plain';
  const head = (s) => (caps ? s.toUpperCase() : s.charAt(0).toUpperCase() + s.slice(1));
  return {
    label: voice === 'caps' ? 'DEKHO' : 'Dekho',
    page: voice === 'bracket' ? 'TITLE' : 'title',
    crew: head('crew'),
    cast: head('cast'),
    nextUp: voice === 'bracket' ? '[NEXT UP]' : caps ? 'NEXT UP' : 'next up',
    filters: upper(voice, 'f filters by these'),
    more: (n) => upper(voice, `${n > 0 ? `+ ${n} · ` : ''}tab to reach, ↵ opens a person`),
    keys: [['j/k', 'episode'], ['h/l', 'season'], ['↵', 'choose a release'], ['r', 'resume'], ['t', 'trailer'], ['w', 'mark watched'], ['tab', 'buttons, seasons, episodes, crew, cast'], ['f', "filter by this title's genre, language, people"], ['/', 'search'], ['esc', 'back']],
  };
}
