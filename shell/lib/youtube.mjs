// What every YouTube view shares: dots-youtube-api's answers read safely, and its rows made fit to draw.
import { oneLine } from './picker.mjs';
export { answer } from './dekho.mjs';

// A video id names a thumbnail's cache file and a URL, so only YouTube's 11 id characters pass.
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;

const two = (n) => String(n).padStart(2, '0');

// yt-dlp gives seconds, or null for a live stream; a row reads 4:27 or 1:02:14.
export function duration(secs) {
  if (typeof secs !== 'number' || !(secs >= 0)) return '';
  const s = Math.floor(secs);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h}:${two(m)}:${two(s % 60)}` : `${m}:${two(s % 60)}`;
}

// YouTube's titles and channels are whatever their uploaders typed, so each draws as one plain line.
export function rows(answer) {
  const list = answer && Array.isArray(answer.rows) ? answer.rows : [];
  const out = [];
  for (const r of list) {
    if (!r || typeof r !== 'object' || !VIDEO_ID.test(r.id)) continue;
    out.push({
      id: r.id,
      title: oneLine(r.title),
      channel: oneLine(r.channel),
      duration: duration(r.duration),
      thumb: VIDEO_ID.test(r.thumb) ? r.thumb : '',
    });
  }
  return out;
}

// Each empty view names the key that fills it, as the first-open boards write it.
export const EMPTY = {
  saved: { head: 'Nothing saved yet', key: 's', rest: 'saves a video' },
  playlists: 'n makes one',
};
