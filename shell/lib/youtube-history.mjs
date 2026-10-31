// The YouTube App's History, ~/.local/state/dots/youtube/history.json: the single videos played, newest first, each video once. Kept pure so node can test it.
import { duration } from './youtube.mjs';

export const MAX = 200;

// A video id names a thumbnail's cache file and a URL, so only YouTube's 11 id characters pass.
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;

export const empty = () => [];

// A bare array, newest first, because the list order is all History keeps; no file yet is an empty History; a file that is broken or not a list is null, so nothing ever saves over a History it could not read.
export function parse(text) {
  if (String(text).trim() === '') return empty();
  let list;
  try {
    list = JSON.parse(text);
  } catch (e) {
    return null;
  }
  if (!Array.isArray(list)) return null;
  const seen = new Set();
  const out = [];
  for (const e of list) {
    if (!e || typeof e !== 'object' || !VIDEO_ID.test(e.id) || seen.has(e.id)) continue;
    seen.add(e.id);
    out.push(e);
  }
  return out;
}

export const serialize = (history) => JSON.stringify(history, null, 1) + '\n';

// An entry keeps secs, not the drawn duration text: rows() draws the text again.
export function add(history, row, now) {
  const entry = { id: row.id, title: row.title, channel: row.channel, duration: row.secs, thumb: row.thumb, at: now };
  return [entry].concat(history.filter((e) => e.id !== row.id)).slice(0, MAX);
}

// The rows a list draws, shaped like youtube.mjs rows() so History and a search draw the same.
export const rows = (history) =>
  history.map((e) => ({ id: e.id, title: e.title, channel: e.channel, duration: duration(e.duration), secs: e.duration, thumb: e.thumb }));
