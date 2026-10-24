// Home's words: a continued title's episode or length and the time left, a trending title's year and rating, in each theme's voice.
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
  return [hit.year, `★ ${Number(hit.vote || 0).toFixed(1)}`].filter((p) => p).join(' · ');
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
    keys: [['h/j/k/l', 'move'], ['↵', 'open'], ['/', 'search'], ['f', 'filters: genre, language, person…'], ['tab', 'next row'], ['esc', 'close']],
  };
}
