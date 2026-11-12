// The control characters and bidi marks the shell cleans from text it did not write. Each set is regex source to put between [ and ], so a caller composes the class its own cleaning needs; every character is an escape, so a reviewer can read each set whole. The new-tab page loads this file beside newtab.mjs, so it imports nothing.

export const C0 = '\\u0000-\\u001f';
// C0 but tab, newline and return, for text that keeps its lines.
export const C0_BUT_LINES = '\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f';
// C0 but newline, for text that keeps its paragraphs and drops its tabs.
export const C0_BUT_LF = '\\u0000-\\u0009\\u000b-\\u001f';
export const DEL = '\\u007f';
export const C1 = '\\u0080-\\u009f';
// Left-to-right and right-to-left marks.
export const LRM_RLM = '\\u200e\\u200f';
// Arabic letter mark.
export const ALM = '\\u061c';
// Embeddings and overrides, LRE to RLO.
export const EMBEDS = '\\u202a-\\u202e';
// Isolates, LRI to PDI.
export const ISOLATES = '\\u2066-\\u2069';
// Zero-width space, non-joiner and joiner.
export const ZERO_WIDTH = '\\u200b-\\u200d';
export const BOM = '\\ufeff';

export const CONTROL_SET = C0 + DEL + C1;
export const MARK_SET = LRM_RLM + ALM;
export const BIDI_SET = MARK_SET + EMBEDS + ISOLATES;

// A class of the sets given; a caller that calls .test() leaves out 'g', since a global regex keeps its lastIndex between calls.
export const klass = (set, flags = '') => new RegExp(`[${set}]`, flags);

// C0, DEL and C1, which a font draws as tofu (U+0085 ends a line).
export const CONTROL = klass(CONTROL_SET, 'g');
// The marks alone, which reorder what follows them.
export const MARK = klass(MARK_SET, 'g');
// The marks, embeddings, overrides and isolates, which let a name redraw itself in another order.
export const BIDI = klass(BIDI_SET, 'g');
