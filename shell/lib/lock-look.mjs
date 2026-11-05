// How the lock screen draws: Artboard's selected card in every colorscheme, the clock on the card and the date as its frame label.

// Lock.qml draws before the theme loads after a crash, so it needs colours of its own.
export const FALLBACK = { paper: 'black', ink: 'white', muted: 'gray', accent: 'white', danger: 'white' };

export function lockLook(tokens, user) {
  const c = tokens ? tokens.color : FALLBACK;
  const t = tokens ? tokens.type : { display: '', ui: '' };
  return {
    kind: 'card',
    status: { text: 'Locked', color: c.ink },
    clock: { family: t.display, px: 96, bold: true, tracking: -4.8, fill: c.ink, stroke: 'transparent' },
    date: { format: 'dddd, d MMMM', caps: false, family: t.ui, px: 12, italic: false, tracking: 0, color: c.accent },
    prompt: '',
    hint: `Password for ${user} · ↵ to unlock`,
  };
}
