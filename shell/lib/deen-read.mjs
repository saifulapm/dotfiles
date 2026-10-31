// Deen's Read: the cursor's moves over a surah's words, the heading and bar lines, and the surah picker's filter.

// The cursor is { a, i }, ayah and word from 1; lengths[k] is ayah k + 1's word count. By 1 is h, the next word to the left.
export function stepWord(lengths, at, by) {
  const i = at.i + by;
  if (i >= 1 && i <= lengths[at.a - 1]) return { a: at.a, i: i };
  const a = at.a + by;
  if (a < 1 || a > lengths.length) return at;
  return { a: a, i: by > 0 ? 1 : lengths[a - 1] };
}

export const stepAyah = (lengths, at, by) => ({ a: Math.max(1, Math.min(lengths.length, at.a + by)), i: 1 });

export const typeName = (type) => (type === 'Medinan' ? 'Madani' : 'Makki');

const say = (voice, s) => (voice === 'bracket' ? s.toUpperCase() : s);

export const headingText = (surah) => surah.bn;

export function metaText(voice, surah, juz) {
  const parts = [`${surah.count} ayat`, typeName(surah.type)];
  if (juz !== null && juz !== undefined) parts.push(`juz ${juz}`);
  return say(voice, parts.join(' · '));
}

// Arabic has no case, so Blueprint's capitals leave the root's letters as they are.
export function wordLine(voice, word, a) {
  const parts = [`ayah ${a}, word ${word.i}`];
  if (word.root) parts.push(`root ${word.root}`);
  return say(voice, parts.join(' · '));
}

export const hearHint = (voice) => (voice === 'bracket' ? '[↵] HEAR THIS WORD' : '↵ hear this word');

// Harakat and Quranic marks, so a name typed bare finds the voweled one.
const MARKS = /[ً-ٰٟۖ-ۭ]/g;
const bare = (s) => String(s || '').replace(MARKS, '').toLowerCase();

export function surahsMatching(surahs, query) {
  const q = bare(query).trim();
  if (!q) return surahs;
  if (/^\d+$/.test(q)) {
    const hits = surahs.filter((s) => String(s.n).indexOf(q) >= 0);
    return hits.filter((s) => String(s.n) === q).concat(hits.filter((s) => String(s.n) !== q));
  }
  return surahs.filter((s) => [s.en, s.tr, s.ar, s.bn].some((name) => bare(name).indexOf(q) >= 0));
}

export const readable = (answer) => !!answer && !answer.error && Array.isArray(answer.ayahs) && answer.ayahs.length > 0 && Array.isArray(answer.words);

export function addedText(answer, name) {
  if (answer && answer.error) return String(answer.error);
  return answer ? `${name} added to Memorise` : `${name} could not be added to Memorise`;
}
