// What a film or episode playing in its unit is, read from dekho play's events, for the now-playing bar.
import { title as line } from './dekho.mjs';

// dekho labels a series' playing event "Show — S01E03  Name" and a film's "Title (year)"; the bar writes a series' episode as S1 · E3.
export function nowPlaying(e) {
  const m = e.kind === 'tv' ? /^([\s\S]*) — S(\d+)E(\d+)(?:\s|$)/.exec(String(e.title ?? '')) : null;
  return { id: e.id, kind: e.kind, title: line(m ? m[1] : e.title), episode: m ? `S${Number(m[2])} · E${Number(m[3])}` : '' };
}

// What plays after these events, in their order: the last playing event's, until the run exits; a run that never played shows nothing.
export function fromEvents(events) {
  let now = null;
  for (const e of events) {
    if (e.event === 'playing') now = nowPlaying(e);
    else if (e.event === 'exit') now = null;
  }
  return now;
}
