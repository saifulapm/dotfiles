// The cheat sheet's rows: every niri bind with a hotkey-overlay-title, its key as the designs write it, and its group, then the touchpad's.
export const GROUPS = ['SURFACES', 'WORK', 'WINDOWS', 'SYSTEM', 'TOUCHPAD'];

// No bind holds these: niri's own swipes and bottom-left corner (gestures.kdl), dots-gestures' pinches, and the margins' Notes corner.
export const TOUCHPAD = [
  ['3-finger ↕', 'Switch Workspace'],
  ['3-finger ↔', 'Scroll Columns'],
  ['4-finger ↕', 'Overview'],
  ['4-finger pinch', 'Launcher'],
  ['4-finger spread', 'Overview'],
  ['↙ corner', 'Overview'],
  ['↗ corner', 'Notes'],
].map(([key, title]) => ({ title, key, group: 'TOUCHPAD' }));

const MODS = { Mod: 'Mod', Shift: '⇧', Ctrl: '⌃', Alt: '⌥', Super: 'Super' };
const KEYS = { Slash: '/', Return: '↵', Page_Up: 'PgUp', Page_Down: 'PgDn', Escape: 'Esc', Period: '.', Comma: ',' };

function keyText(combo, title) {
  // A media key has no printed name the designs use, so its row shows the title.
  if (combo.startsWith('XF86')) return title;
  const parts = combo.split('+');
  const key = parts.pop();
  return parts.map((m) => MODS[m] || m).concat([KEYS[key] || key]).join(' ');
}

function groupOf(combo, action) {
  if (combo.startsWith('XF86')) return 'SYSTEM';
  if (/^spawn "qs" "ipc" "call"/.test(action)) return 'SURFACES';
  if (/^spawn\b/.test(action)) return 'WORK';
  if (/window|column|workspace/.test(action)) return 'WINDOWS';
  return 'SYSTEM';
}

export function parseBinds(text) {
  const rows = [];
  for (const line of text.split('\n')) {
    const m = line.match(/^\s*(\S+)\s([^{]*)\{(.*)\}\s*$/);
    const title = m && m[2].match(/hotkey-overlay-title="([^"]*)"/);
    if (!title) continue;
    rows.push({ title: title[1], key: keyText(m[1], title[1]), group: groupOf(m[1], m[3].trim()) });
  }
  return rows;
}

export function groupRows(rows) {
  return GROUPS.map((name) => ({ name, rows: rows.filter((r) => r.group === name) }));
}

// SYSTEM is the shortest group, so the touchpad sits under it and the sheet keeps four columns.
export function columnsOf(groups) {
  return [groups.slice(0, 1), groups.slice(1, 2), groups.slice(2, 3), groups.slice(3)];
}

export function filterRows(rows, query) {
  const q = query.toLowerCase();
  return rows.filter((r) => r.title.toLowerCase().includes(q) || r.key.toLowerCase().includes(q));
}
