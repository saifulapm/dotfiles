// How the lock screen draws under a token set, from its frame primitive, as the three lock designs do.

// Lock.qml draws before the theme loads after a crash, so it needs colours of its own.
export const FALLBACK = { paper: 'black', ink: 'white', muted: 'gray', accent: 'white', danger: 'white' };

export function lockLook(tokens, user) {
  const c = tokens ? tokens.color : FALLBACK;
  const t = tokens ? tokens.type : { display: '', ui: '' };
  const frame = tokens ? tokens.primitive.frame : 'ink';
  const prompt = 'PASSWORD FOR ' + user.toUpperCase();
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
  // Blueprint: a drawing sheet with a hollow clock and the date on a dimension line.
  if (frame === 'glow') {
    return {
      kind: 'sheet',
      status: { text: '[LOCKED]', color: c.danger },
      clock: { family: t.display, px: 200, bold: true, tracking: -4, fill: 'transparent', stroke: c.accent },
      date: { format: 'yyyy-MM-dd · dddd', caps: true, family: t.ui, px: 11, italic: false, tracking: 2.2, color: c.accent },
      prompt,
      hint: '[↵] UNLOCK',
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
