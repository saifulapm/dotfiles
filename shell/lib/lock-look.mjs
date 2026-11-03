// How the lock screen draws under a token set, from its frame primitive, as the four lock designs do.

import { plainTones, marginLook } from './voice.mjs';

// The words on the bar's right, from the margins' wifi and battery words: Frost writes them as its desktop bar does, Hi-Fi in caps.
export function lockMeter(tokens, wifi, battery) {
  const words = [wifi, battery].filter((w) => w !== '');
  return tokens?.niri?.blur === true ? words.map(marginLook(tokens).word).join(' ') : words.join(' ').toUpperCase();
}

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
      // A closed padlock in a 14-unit box before the word, as the lock board draws it.
      status: { text: 'Locked', color: c.ink, icon: 'M 4 6 H 10 A 1.5 1.5 0 0 1 11.5 7.5 V 11 A 1.5 1.5 0 0 1 10 12.5 H 4 A 1.5 1.5 0 0 1 2.5 11 V 7.5 A 1.5 1.5 0 0 1 4 6 Z M 4.5 6 V 4.5 A 2.5 2.5 0 0 1 9.5 4.5 V 6', iconColor: c.muted },
      host,
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
