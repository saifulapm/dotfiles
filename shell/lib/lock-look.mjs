// How the lock screen draws under a token set, from its frame primitive, as the four lock designs do.

import { plainTones } from './voice.mjs';

// Lock.qml draws before the theme loads after a crash, so it needs colours of its own.
export const FALLBACK = { paper: 'black', ink: 'white', muted: 'gray', accent: 'white', danger: 'white' };

export function lockLook(tokens, user, host = '') {
  const c = tokens ? tokens.color : FALLBACK;
  const t = tokens ? tokens.type : { display: '', ui: '' };
  const frame = tokens ? tokens.primitive.frame : 'ink';
  const prompt = 'PASSWORD FOR ' + user.toUpperCase();
  // Frost: a light snow clock over frost heavier than the desktop's, from 30 % of the way out, and a glass field. Its frame is a hairline like Paper's, so blur decides it first.
  if (tokens && tokens.niri?.blur === true) {
    return {
      kind: 'frost',
      status: { text: 'Locked', color: c.ink },
      clock: { family: t.display, px: 168, bold: false, weight: 'light', tracking: -5.04, fill: plainTones(tokens).strong, stroke: 'transparent' },
      date: { format: 'dddd, d MMMM', caps: false, family: t.ui, px: 20, italic: false, tracking: 0, color: c.ink },
      prompt: `Password for ${user}`,
      hint: '↵ Unlock',
      dots: plainTones(tokens).strong,
      paper: { start: 0.3, grain: 0.3, vein: 0.4 },
    };
  }
  // Artboard: the clock sits on a selected card and the date is the card's frame label.
  if (frame === 'none') {
    return {
      kind: 'card',
      status: { text: 'Locked', color: c.ink },
      clock: { family: t.display, px: 96, bold: true, tracking: -4.8, fill: c.ink, stroke: 'transparent' },
      date: { format: 'dddd, d MMMM', caps: false, family: t.ui, px: 12, italic: false, tracking: 0, color: c.accent },
      prompt: '',
      hint: `Password for ${user} · ↵ to unlock`,
    };
  }
  // Hi-Fi: a stereo receiver's front panel named after the machine, the clock lit amber in its glass dial; red shows only as the lamp before LOCKED.
  if (tokens && tokens.type.engraved === true) {
    return {
      kind: 'receiver',
      status: { text: 'LOCKED', color: c.ink },
      host: `${host.toUpperCase()} · STEREO RECEIVER`,
      clock: { family: t.display, px: 160, bold: false, tracking: 3.2, fill: c.accent, stroke: 'transparent', glow: c.accent },
      date: { format: 'dddd · d MMMM', caps: true, family: t.ui, px: 12, italic: false, tracking: 3.6, color: c.ink },
      prompt,
      hint: '↵ UNLOCK',
      fieldMarks: [],
    };
  }
  // Blueprint: a drawing sheet with a hollow clock and the date on a dimension line.
  if (frame === 'glow') {
    return {
      kind: 'sheet',
      status: { text: '[LOCKED]', color: c.danger },
      clock: { family: t.display, px: 200, bold: true, tracking: -4, fill: 'transparent', stroke: c.accent },
      date: { format: 'yyyy-MM-dd · dddd', caps: true, family: t.ui, px: 11, italic: false, tracking: 2.2, color: c.accent },
      prompt,
      hint: '[↵] UNLOCK',
      fieldMarks: ['[', ']'],
    };
  }
  // Paper: a printed page, a large serif clock over an italic date.
  return {
    kind: 'print',
    status: { text: 'LOCKED', color: c.muted },
    clock: { family: t.display, px: 220, bold: false, tracking: -4.4, fill: c.ink, stroke: 'transparent' },
    date: { format: 'dddd, d MMMM', caps: false, family: t.display, px: 30, italic: true, tracking: 0, color: c.muted },
    prompt,
    hint: 'press return to unlock',
  };
}
