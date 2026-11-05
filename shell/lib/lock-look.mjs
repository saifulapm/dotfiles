import { readable } from './voice.mjs';
import { bengaliFamily } from './deen.mjs';

// How the lock screen draws: no card, the clock and date at the top of a bare ground, the day's other passage under them, the field low.

// Lock.qml draws before the theme loads after a crash, so it needs colours of its own.
export const FALLBACK = { paper: 'black', ink: 'white', muted: 'gray', accent: 'white', danger: 'white' };

export function lockLook(tokens, user) {
  const c = tokens ? tokens.color : FALLBACK;
  const t = tokens ? tokens.type : { display: '', ui: '' };
  // The old card's surface fills the screen, since a scheme's ink reads at 4.5:1 on its surface and not always on its paper.
  const ground = tokens ? c.surface : c.paper;
  // The quiet lines and the accent, moved toward the ink where they read under 4.5:1 on the ground.
  const quiet = tokens ? readable(c.muted, ground, c.ink) : c.muted;
  const accent = tokens ? readable(c.accent, ground, c.ink) : c.accent;
  return {
    kind: 'open',
    ground,
    clock: { family: t.display, px: 120, bold: true, tracking: -6, fill: c.ink, stroke: 'transparent' },
    date: { format: 'dddd, d MMMM', caps: false, family: t.ui, px: 15, italic: false, tracking: 0, color: quiet },
    // The paper's passage look at about three quarters, every line centred.
    passage: {
      width: 720,
      gap: 18,
      label: { font: t.ui, size: 13, color: accent },
      ar: { size: 46, color: c.ink },
      pron: { font: bengaliFamily, size: 17, height: 1.6, color: quiet },
      bn: { font: bengaliFamily, size: 21, height: 1.6, color: c.ink },
      en: { font: t.ui, size: 20, height: 1.55, color: c.ink },
      ref: { font: t.ui, size: 14, color: quiet },
      bnRef: { font: bengaliFamily, size: 15 },
    },
    prompt: '',
    hint: `Password for ${user} · ↵ to unlock`,
  };
}
