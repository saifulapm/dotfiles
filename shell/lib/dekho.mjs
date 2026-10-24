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
