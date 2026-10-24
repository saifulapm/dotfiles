// The release list and Starting: releases best first, and the steps, progress and rates read from dekho play's events.
const UNITS = ['B', 'KB', 'MB', 'GB', 'TB'];
const MB = 1024 * 1024;

// Best first as v1 ranked them: more seeders, then the bigger file; a missing count or size ranks last.
export function rank(items) {
  return items.slice().sort((a, b) => (b.seeders ?? -1) - (a.seeders ?? -1) || (b.size_bytes ?? -1) - (a.size_bytes ?? -1));
}

// 1024-based like the backend's format_bytes: whole numbers from 10 up, one decimal below.
const unitOf = (n) => {
  let i = 0;
  while (n >= 1024 ** (i + 1) && i < UNITS.length - 1) i++;
  return i;
};
const amount = (n, i) => {
  const v = n / 1024 ** i;
  return i === 0 || v >= 10 || v === 0 ? String(Math.round(v)) : v.toFixed(1);
};

export const sizeText = (n) => `${amount(n, unitOf(n))} ${UNITS[unitOf(n)]}`;

// Both amounts in the whole's unit, as the board writes "41 of 108 MB".
export function ofText(part, whole) {
  const i = unitOf(whole);
  return `${amount(part, i)} of ${amount(whole, i)} ${UNITS[i]}`;
}

// The backend counts bits per second; the board writes megabytes a second.
export const rateText = (bps) => `${((bps || 0) / 8 / MB).toFixed(1)} MB/s`;

// What the Starting board draws after these events, in their order.
export function starting(events) {
  let trying = null;
  let buffer = null;
  let connected = false;
  let ready = false;
  let playing = false;
  for (const e of events) {
    if (e.event === 'trying') trying = e;
    else if (e.event === 'buffer') {
      buffer = e;
      if (e.peers > 0) connected = true;
    } else if (e.event === 'ready') ready = true;
    else if (e.event === 'playing') playing = true;
  }
  const steps = [];
  if (trying) steps.push({ text: `Found ${trying.seeders ?? 0} seeders`, done: connected || ready || playing });
  if (connected) {
    steps.push({ text: 'Connected to peers', done: true });
    steps.push({ text: 'Buffering the start of the file', done: ready || playing });
    if (buffer.needed_bytes) steps.push({ text: `mpv starts at ${sizeText(buffer.needed_bytes)}`, done: playing });
  }
  const at = steps.findIndex((s) => !s.done);
  const needed = buffer && buffer.needed_bytes;
  const progress = ready || playing ? 1 : needed ? Math.min(1, (buffer.bytes || 0) / needed) : 0;
  return {
    steps: steps.map((s, i) => ({ text: s.text, state: s.done ? 'done' : i === at ? 'current' : 'pending' })),
    progress,
    percent: `buffering ${Math.round(progress * 100)}%`,
    amount: needed ? ofText(Math.min(buffer.bytes || 0, needed), needed) : '',
    peers: buffer ? `${buffer.peers || 0} peers · ${buffer.sending || 0} sending` : '',
    down: buffer ? `${rateText(buffer.down_bps)} down` : '',
    up: buffer ? `${rateText(buffer.up_bps)} up` : '',
    release: trying ? [trying.quality, trying.size].filter((p) => p).join(' · ') : '',
    playing,
  };
}

// The words each board writes on the release list, Starting and no releases.
export function releasesText(voice) {
  const caps = voice !== 'plain';
  const up = (s) => (voice === 'bracket' ? s.toUpperCase() : s);
  return {
    release: caps ? 'RELEASE' : 'Release',
    starting: caps ? 'STARTING' : 'Starting',
    count: (n) => up(`${n} release${n === 1 ? '' : 's'}`),
    columns: (caps ? ['QUALITY', 'SIZE', 'SEEDERS', 'AUDIO'] : ['Quality', 'Size', 'Seeders', 'Audio']),
    best: voice === 'bracket' ? '[BEST]' : caps ? 'BEST' : 'best',
    up,
    keys: [['↵', 'stream'], ['j/k', 'move'], ['esc', 'back']],
    startKeys: [['esc', 'cancel and stop the download']],
    none: 'No releases found',
    noneWhy: 'Both sources answered and neither lists this episode yet.',
    noneToday: 'It aired today, and releases often take a day to appear.',
    tryHead: caps ? 'WHAT TO TRY' : 'What to try',
    tries: [['r', 'ask again in a few minutes'], ['/', 'search by name for a season pack'], ['esc', 'go back and pick an earlier episode']],
    noneKeys: [['r', 'ask again'], ['/', 'search by name'], ['esc', 'back']],
  };
}
