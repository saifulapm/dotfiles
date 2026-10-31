// Deen's Memorise page: today's due cards one at a time, what each theme says over them, and the list as it shrinks while Saiful rates himself.

const upper = (s) => s.toUpperCase();

// How long until a card comes back, in the unit that reads best: minutes, hours, days, past 60 days months.
export function nextText(voice, seconds) {
  const plural = (n, unit) => `${n} ${unit}${n === 1 ? '' : 's'}`;
  const days = Math.floor(seconds / 86400);
  let text;
  if (seconds < 3600) text = `${Math.max(1, Math.floor(seconds / 60))} min`;
  else if (seconds < 86400) text = plural(Math.floor(seconds / 3600), 'hour');
  else if (days > 60) text = plural(Math.floor(days / 30), 'month');
  else text = plural(days, 'day');
  return voice === 'bracket' ? upper(text) : text;
}

// The first half of the ayah's words as a cue, one to five of them, and how many are left to recite.
export function firstWords(ar) {
  const all = String(ar ?? '')
    .split(/\s+/)
    .filter((w) => w !== '');
  const n = Math.min(5, Math.max(1, Math.floor(all.length / 2)));
  return { shown: all.slice(0, n).join(' '), hidden: Math.max(0, all.length - n) };
}

// A number in Bangla digits, as a reference beside a Bangla name is written.
const bnDigits = (n) => String(n).replace(/[0-9]/g, (d) => '০১২৩৪৫৬৭৮৯'[d]);

// The surah's Bangla name for a card's heading; the number stands in until the names are known.
export function surahName(answer, n) {
  const list = answer && Array.isArray(answer.surahs) ? answer.surahs : [];
  const found = list.find((s) => s && s.n === n);
  return found && typeof found.bn === 'string' && found.bn !== '' ? found.bn : `সূরা ${bnDigits(n)}`;
}

// The deck as `deen hifz due` answers it, or null when that is no deck.
export function openDeck(answer) {
  if (!answer || !Array.isArray(answer.due)) return null;
  const cards = answer.due.filter((d) => d && typeof d.reference === 'string' && d.ayah && typeof d.ayah.ar === 'string' && d.next && typeof d.next === 'object');
  return {
    cards,
    left: Number.isInteger(answer.total_due) ? answer.total_due : cards.length,
    fresh: Number.isInteger(answer.new_due) ? answer.new_due : 0,
    rated: 0,
    nextIn: null,
  };
}

export const current = (s) => (s.cards.length > 0 ? s.cards[0] : null);

// The deck after the head card was graded, or null when the grade did not save, so the card stays.
export function rate(s, graded) {
  if (!graded || typeof graded.reference !== 'string' || !graded.card) return null;
  const head = current(s);
  if (!head || head.reference !== graded.reference) return null;
  const back = typeof graded.due_in_days === 'number' ? graded.due_in_days * 86400 : null;
  return {
    cards: s.cards.slice(1),
    left: Math.max(0, s.left - 1),
    fresh: head.card && head.card.reps === 0 ? Math.max(0, s.fresh - 1) : s.fresh,
    rated: s.rated + 1,
    nextIn: back === null ? s.nextIn : s.nextIn === null ? back : Math.min(s.nextIn, back),
  };
}

// The head card goes to the end unrated; the count stays.
export const skip = (s) => Object.assign({}, s, { cards: s.cards.slice(1).concat(s.cards.slice(0, 1)) });

// What each theme's board says: Paper keeps its caps for the labels, Artboard is all sentence case, Blueprint is all capitals.
export function words(voice) {
  const t = voice === 'bracket' ? upper : (s) => s;
  const label = voice === 'plain' ? (s) => s : upper;
  const badge = (revealed) => {
    const text = label(revealed ? '2 · revealed' : '1 · recall');
    return voice === 'bracket' ? `[${text}]` : text;
  };
  return {
    due: (n) => t(`${n} due today`),
    line: (fresh, at, left) => t(`${fresh} new · ${at} of ${left} · self-graded, nothing is recorded`),
    quiet: t('self-graded, nothing is recorded'),
    badge,
    heading: (name, s, a) => `${name} ${bnDigits(s)}:${bnDigits(a)}`,
    recite: t('Recite the rest aloud. No microphone: you judge yourself.'),
    hintKey: voice === 'bracket' ? '[SPACE]' : 'space',
    hintWord: t('reveal the rest'),
    ask: label('How did it go · next review'),
    grades: ['again', 'hard', 'good', 'easy'].map(t),
    done: (back) => t(back === null ? 'Done for today.' : `Done for today. Next review in ${nextText('caps', back)}.`),
    nothing: t('Nothing due today. Press m in Read to add a surah to Memorise.'),
    failed: t('Could not read the deck.'),
    unsaved: t('Could not save that rating. Try again.'),
  };
}

// When the first card rated so far comes back, in ms since the epoch; a grade that did not save changes nothing.
export function backAt(prev, now, graded) {
  if (!graded || typeof graded.due_in_days !== 'number') return prev;
  const at = now + Math.round(graded.due_in_days * 86400000);
  return prev === null ? at : Math.min(prev, at);
}

// A page that has rated every card asks for the deck again once a rated card is due, so an Again card shows ten minutes on.
export const reloadNow = (status, at, now) => status === 'done' && at !== null && now >= at;
