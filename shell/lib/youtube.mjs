// What every YouTube view shares: dots-youtube-api's answers read safely, and its rows made fit to draw.
import { oneLine } from './picker.mjs';
export { answer } from './dekho.mjs';

// A video id names a thumbnail's cache file and a URL, so only YouTube's 11 id characters pass; a playlist's is YouTube's PL, OLAK5uy_ or RD run, a channel's UC and 22 more.
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const IDS = { video: VIDEO_ID, playlist: /^[A-Za-z0-9_-]{2,64}$/, channel: /^UC[A-Za-z0-9_-]{22}$/ };

const two = (n) => String(n).padStart(2, '0');

// yt-dlp gives seconds, or null for a live stream; a row reads 4:27 or 1:02:14.
export function duration(secs) {
  if (typeof secs !== 'number' || !(secs >= 0)) return '';
  const s = Math.floor(secs);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h}:${two(m)}:${two(s % 60)}` : `${m}:${two(s % 60)}`;
}

// A playlist row draws its count where a video draws its duration: 1 video, 1,234 videos.
export function count(n) {
  if (!Number.isInteger(n) || n < 0) return '';
  return `${String(n).replace(/\B(?=(\d{3})+$)/g, ',')} ${n === 1 ? 'video' : 'videos'}`;
}

// YouTube's titles and channels are whatever their uploaders typed, so each draws as one plain line. Saved and History keep rows from before kinds, so a row with none is a video.
export function rows(answer) {
  const list = answer && Array.isArray(answer.rows) ? answer.rows : [];
  const out = [];
  for (const r of list) {
    if (!r || typeof r !== 'object') continue;
    const kind = r.kind === undefined ? 'video' : r.kind;
    if (!Object.prototype.hasOwnProperty.call(IDS, kind) || !IDS[kind].test(r.id)) continue;
    const row = {
      id: r.id,
      kind,
      title: oneLine(r.title),
      channel: oneLine(r.channel),
      duration: kind === 'playlist' ? count(r.count) : duration(r.duration),
      secs: kind === 'video' && duration(r.duration) ? r.duration : null,
      thumb: VIDEO_ID.test(r.thumb) ? r.thumb : '',
    };
    if (kind === 'playlist') row.count = count(r.count) ? r.count : null;
    out.push(row);
  }
  return out;
}

// A failed call's error is the line the list shows, raw is yt-dlp's own ERROR line or empty; an answer with no JSON at all fails too, so the list never draws empty for it.
export function failure(answer) {
  if (!answer || typeof answer !== 'object' || Array.isArray(answer)) return { error: 'dots-youtube-api gave no answer', kind: '', raw: '' };
  if (typeof answer.error !== 'string' || answer.error === '') return null;
  const text = (v) => (typeof v === 'string' ? oneLine(v) : '');
  return { error: oneLine(answer.error), kind: text(answer.kind), raw: text(answer.raw) };
}

// Each empty view names the key that fills it, as the first-open boards write it.
export const EMPTY = {
  saved: { head: 'Nothing saved yet', key: 's', rest: 'saves a video' },
  playlists: 'n makes one',
};
