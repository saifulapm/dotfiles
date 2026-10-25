// What a film or episode playing in its unit is, read from dekho play's events, for the now-playing bar.
import { title as line } from './dekho.mjs';

// dekho labels a series' playing event "Show — S01E03  Name" and a film's "Title (year)"; the bar writes a series' episode as S1 · E3. Either name can hold that same tag, so the show's own name, when known, says where dekho joined them; without it the first tag is taken. show keeps the show's name as dekho wrote it, title the line the bar draws.
export function nowPlaying(e, show = '') {
  const label = String(e.title ?? '');
  let m = null;
  if (e.kind === 'tv') {
    const known = show && label.startsWith(`${show} — S`) ? /^S(\d+)E(\d+)(?:\s|$)/.exec(label.slice(show.length + 3)) : null;
    m = known ? [label, show, known[1], known[2]] : /^([\s\S]*?) — S(\d+)E(\d+)(?:\s|$)/.exec(label);
  }
  return { id: e.id, kind: e.kind, title: line(m ? m[1] : label), show: m ? m[1] : '', episode: m ? `S${Number(m[2])} · E${Number(m[3])}` : '' };
}

// dekho sends no event when mpv moves on to a series' next episode, but titles each file it appends, and mpv titles its window "<media-title> - mpv": the film unit's own mpv window names the episode on screen. Anything else leaves what plays as it was.
export function fromWindow(now, text, pids) {
  if (!now || now.kind !== 'tv') return now;
  let windows;
  try {
    windows = JSON.parse(String(text));
  } catch (e) {
    return now;
  }
  const own = Array.isArray(windows) ? windows.find((w) => w && w.app_id === 'mpv' && pids.includes(w.pid)) : null;
  if (!own) return now;
  const seen = nowPlaying({ kind: 'tv', id: now.id, title: String(own.title ?? '').replace(/ - mpv$/, '') }, now.show);
  return seen.episode && seen.show === now.show && seen.episode !== now.episode ? Object.assign({}, now, { episode: seen.episode }) : now;
}

// The bar's words: its tag in each board's voice, and its key as the keys strip names keys.
export function barText(voice) {
  return {
    tag: voice === 'bracket' ? '[NOW PLAYING]' : voice === 'caps' ? 'NOW PLAYING' : 'Now playing',
    keys: [['⇧S', 'stop']],
  };
}
