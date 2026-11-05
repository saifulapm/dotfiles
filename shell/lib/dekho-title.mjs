// The Title page's words and choices: which episode is next up, how a date and the watched count read, which crew to name.
import { stars } from './dekho.mjs';
import { resumeLine } from './dekho-home.mjs';
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

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

export function dateText(airDate, today) {
  if (!airDate) return '';
  const [, m, d] = airDate.split('-').map(Number);
  const day = `${d} ${MONTHS[m - 1]}`;
  return airDate <= today ? day : `airs ${day}`;
}

export function watchedText(items) {
  return `${items.filter((ep) => ep.watched).length} of ${items.length} watched`;
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

export function metaText(title) {
  const min = Math.round((title.runtime || 0) / 60);
  const tv = title.kind === 'tv';
  const ended = tv && title.in_production === false && title.last_air;
  const years = tv ? `${title.year} –${ended ? ` ${title.last_air.slice(0, 4)}` : ''}` : title.year;
  const length = !min ? '' : tv ? `${min} min episodes` : clock(min);
  return [years, stars(title.vote), length].filter((p) => p).join(' · ');
}

export const episodeLength = (secs) => (secs ? `${Math.round(secs / 60)} min` : '');

export function sideText(title) {
  const n = title.season_count;
  const seasons = title.kind === 'tv' && n ? `${n} season${n === 1 ? '' : 's'}` : '';
  return (title.genres || []).concat(seasons ? [seasons] : []).join(' · ');
}

// History's entry for a title still being watched: the same id and kind, not finished; else null.
export function watching(history, title) {
  const seen = (history || []).find((h) => h && h.id === title.id && h.kind === title.kind);
  return seen && !seen.finished ? seen : null;
}

// The title's buttons: Play always, Resume with what is left while history holds it, and Trailer when the title has one.
export function buttons(seen, trailer) {
  const out = [{ id: 'play', text: '▶ Play' }];
  if (seen) out.push({ id: 'resume', text: ['▶ Resume', resumeLine(seen)].filter((p) => p).join(' · ') });
  if (trailer) out.push({ id: 'trailer', text: '▶ Trailer' });
  return out;
}

// The line under the meta line; the page cleans its text for drawing, this only picks it.
export const tagline = (title) => (typeof title.tagline === 'string' ? title.tagline.trim() : '');

// The title's links in the order drawn. The imdb id lands in a URL and the homepage is opened as given, so each is checked: an id as tt and digits, a homepage as http(s) with no space, control or bidi character.
export function links(title) {
  const out = [{ id: 'tmdb', text: 'TMDB', url: `https://www.themoviedb.org/${title.kind === 'tv' ? 'tv' : 'movie'}/${title.id}` }];
  if (typeof title.imdb_id === 'string' && /^tt[0-9]+$/.test(title.imdb_id)) out.push({ id: 'imdb', text: 'IMDb', url: `https://www.imdb.com/title/${title.imdb_id}` });
  if (typeof title.homepage === 'string' && /^https?:\/\/[^\s\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]+$/.test(title.homepage)) out.push({ id: 'homepage', text: 'Homepage', url: title.homepage });
  return out;
}

// More like this draws the first 10 of the title's similar titles.
export const similar = (title) => (Array.isArray(title.similar) ? title.similar.slice(0, 10) : []);

// The words the board writes on the Title page.
export function titleText() {
  return {
    label: 'Dekho',
    page: 'title',
    crew: 'Crew',
    cast: 'Cast',
    similar: 'More like this',
    nextUp: 'next up',
    filters: 'f filters by these',
    more: (n) => `${n > 0 ? `+ ${n} · ` : ''}tab to reach, ↵ opens a person`,
    keys: [['j/k', 'episode'], ['h/l', 'season'], ['↵', 'choose a release'], ['r', 'resume'], ['t', 'trailer'], ['w', 'mark watched'], ['tab', 'buttons, links, seasons, episodes, crew, cast, more like this'], ['f', "filter by this title's genre, language, people"], ['/', 'search'], ['esc', 'back']],
  };
}
