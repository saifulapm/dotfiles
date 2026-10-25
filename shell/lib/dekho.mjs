// What every Dekho page shares: the backend's answers read safely, and its text made fit to draw.
import { oneLine } from './picker.mjs';

// TMDB's titles and names are whatever their editors typed, so each draws as one plain line.
export const title = (s) => oneLine(s);

// dekho api prints one JSON object; anything else, a crash's text or nothing, is no answer.
export function answer(text) {
  let a;
  try {
    a = JSON.parse(String(text));
  } catch (e) {
    return null;
  }
  return a && typeof a === 'object' && !Array.isArray(a) ? a : null;
}

// TMDB gives 0 to a title nobody has voted on, which would read as the worst rating, so it reads nothing.
export const stars = (vote) => (Number(vote) > 0 ? `★ ${Number(vote).toFixed(1)}` : '');

// A TMDB image path prefetch may be asked for: the real dekho fails the whole call on any other, and the file it answers becomes a file URL.
export const picturePath = (p) => typeof p === 'string' && /^\/[A-Za-z0-9_-]+\.[A-Za-z0-9]+$/.test(p);

// One list's paths for one prefetch call: each well-formed path once, past those already on disk.
export function wanted(paths, held) {
  const out = [];
  for (const p of paths) if (picturePath(p) && !held[p] && !out.includes(p)) out.push(p);
  return out;
}

// What is on disk once an answer lands: the files it lists for the paths asked; an error or no answer adds nothing.
export function withFiles(held, answer, asked) {
  const files = answer && answer.files && typeof answer.files === 'object' ? answer.files : {};
  const out = Object.assign({}, held);
  for (const p of asked) if (typeof files[p] === 'string' && files[p].startsWith('/')) out[p] = files[p];
  return out;
}
