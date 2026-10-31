// What every Deen page shares: its tabs, the backend's answers read safely, and outside text made fit to draw.
import { oneLine as pickerLine } from './picker.mjs';

export const TABS = ['read', 'memorise', 'duas', 'hadith', 'prayer'];

export const tabName = (tab) => tab.charAt(0).toUpperCase() + tab.slice(1);

export function tabAfter(tab, by) {
  const i = TABS.indexOf(tab);
  return i < 0 ? TABS[0] : TABS[(i + by + TABS.length) % TABS.length];
}

// deen prints one JSON object; anything else, a crash's text or nothing, is no answer.
export function answer(text) {
  let a;
  try {
    a = JSON.parse(String(text));
  } catch (e) {
    return null;
  }
  return a && typeof a === 'object' && !Array.isArray(a) ? a : null;
}

// A query, a dua or a hadith is whatever its source holds, so where it draws as one line the controls and the bidi overrides and isolates go; Arabic's own letters and harakat stay.
export const oneLine = (s) => pickerLine(String(s ?? '').replace(/[‪-‮⁦-⁩]/g, ''));

// Amiri is the boards' face; until a machine has it, Noto Naskh Arabic, which every machine has, draws the Arabic.
export const arabicFamily = (families) => (families.indexOf('Amiri') >= 0 ? 'Amiri' : 'Noto Naskh Arabic');

// Paper's serif Bangla matches its Fraunces; Artboard and Blueprint draw sans.
export const bengaliFamily = (voice) => (voice === 'caps' ? 'Noto Serif Bengali' : 'Noto Sans Bengali');

// Drawn as it is in every theme: Blueprint's capitals would change the commands it names.
export const NO_DATA = 'Bangla data is not on this machine: gh auth login, then dots update';

const NO_TEXT = ['cannot read the Quran text at ', 'cannot read the duas at '];

// deen cannot read its data files, or its surah's words come from data older than their Bangla meanings.
export function noData(answer) {
  if (!answer) return false;
  if (typeof answer.error === 'string') return NO_TEXT.some((p) => answer.error.startsWith(p));
  if (!Array.isArray(answer.words) || answer.words.length === 0) return false;
  return !answer.words.some((ws) => Array.isArray(ws) && ws.some((w) => w && typeof w.bn === 'string' && w.bn !== ''));
}
