// Pure pieces of the island, kept here so node can test them.

import { clockText } from './margins.mjs';

// The calendar is opened by hand from rest, so only a question takes the island from it (2CJT7F6Q, C3NHPE5Z).
const PRIORITY = ['question', 'calendar', 'notification', 'recording', 'osd', 'toast', 'playing'];

export const MAX_WIDTH = 560;

// Each slot is null when it has nothing to show.
export const pick = (slots) => PRIORITY.find((k) => slots[k]) ?? 'rest';

const joined = (parts) => parts.filter((p) => p).join(' · ');

// `qs ipc call island state` reports this text, whatever the theme draws.
export function islandText(mode, slots, now) {
  switch (mode) {
    case 'question':
      return [slots.question.text, ...slots.question.options.map((o, i) => `[${i + 1}] ${o}`)].join('  ');
    case 'notification':
      return joined([slots.notification.app, slots.notification.summary, slots.notification.body]);
    case 'recording':
      return `● ${slots.recording}`;
    case 'osd':
      return `${slots.osd.kind === 'volume' ? 'Volume' : 'Brightness'} ${slots.osd.value}%`;
    case 'toast':
      return slots.toast;
    case 'playing':
      return `${[slots.playing.title, slots.playing.artist].filter((p) => p).join(' — ')}  ${clockText(now)}`;
    default:
      return slots.notice || clockText(now);
  }
}

export const boxWidth = (contentWidth) => Math.min(contentWidth, MAX_WIDTH);
