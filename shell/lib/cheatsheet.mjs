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
const KEYS = { Slash: '/', Return: '↵', Page_Up: 'PgUp', Page_Down: 'PgDn', Escape: 'Esc', Period: '.', Comma: ',', Semicolon: ';', Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']' };

// media: each bare media key's title, which names that key under a modifier too.
function keyText(combo, title, media) {
  const parts = combo.split('+');
  const key = parts.pop();
  // A media key has no printed name the designs use, so its row shows the title, or the bare key's behind a modifier.
  const name = key.startsWith('XF86') ? (parts.length ? media[key] || title : title) : KEYS[key] || key;
  return parts.map((m) => MODS[m] || m).concat([name]).join(' ');
}

function groupOf(combo, action) {
  if (combo.split('+').pop().startsWith('XF86')) return 'SYSTEM';
  if (/^spawn "(qs" "ipc" "call|dots-call)"/.test(action)) return 'SURFACES';
  // nirius moves windows, so its binds are window binds though they spawn.
  if (/^spawn "(nirius|dots-scratchpad)"/.test(action)) return 'WINDOWS';
  if (/^spawn\b/.test(action)) return 'WORK';
  if (/window|column|workspace/.test(action)) return 'WINDOWS';
  return 'SYSTEM';
}

export function parseBinds(text) {
  const binds = [];
  for (const line of text.split('\n')) {
    const m = line.match(/^\s*(\S+)\s([^{]*)\{(.*)\}\s*$/);
    const title = m && m[2].match(/hotkey-overlay-title="([^"]*)"/);
    if (title) binds.push({ combo: m[1], title: title[1], action: m[3].trim() });
  }
  // QML's engine has no Object.fromEntries.
  const media = {};
  for (const b of binds) if (b.combo.startsWith('XF86')) media[b.combo] = b.title;
  return binds.map((b) => ({ title: b.title, key: keyText(b.combo, b.title, media), group: groupOf(b.combo, b.action) }));
}

export function groupRows(rows) {
  return GROUPS.map((name) => ({ name, rows: rows.filter((r) => r.group === name) }));
}

// SYSTEM is the shortest group, so the touchpad sits under it and the sheet keeps four columns.
export function columnsOf(groups) {
  return [groups.slice(0, 1), groups.slice(1, 2), groups.slice(2, 3), groups.slice(3)];
}

export const GROUPS_SIX = ['SURFACES', 'IN SURFACES', 'WORK', 'WINDOWS', 'SYSTEM', 'TOUCHPAD'];

// No surface shows key hints, so these rows are where its keys are listed: the keys all eight take alike, then each one's own.
export const IN_SURFACES = [
  ['shared', 'Esc', 'Close'],
  // The launcher's and Pass's query fields type j and k until Tab moves to the list.
  ['shared', 'J / K', 'Move Down or Up'],
  ['launcher', '↑ / ↓', 'Move from the Query'],
  ['launcher', 'Tab', 'Go to the List'],
  ['launcher', '↵', 'Open'],
  ['launcher', '⇧ ↵', 'Copy Without Pasting'],
  ['launcher', 'w␣', 'Search Windows'],
  ['launcher', '=␣', 'Calculator'],
  ['control', 'Tab', 'Next Section'],
  ['control', '⇧ Tab', 'Previous Section'],
  ['control', '↵', 'Toggle or Open'],
  ['control', 'H / L', 'Step a Level'],
  ['control', 'M', 'Mute'],
  ['notifications', '↵', 'Open'],
  ['notifications', 'D', 'Dismiss'],
  ['notifications', '⇧ D', 'Clear All'],
  ['notifications', 'I', 'Do Not Disturb for the App'],
  ['notifications', '/', 'Search'],
  ['notifications', '1-9', 'Run an Action'],
  ['pass', 'Tab', 'Go to the List'],
  ['pass', '↵', 'Copy Password'],
  ['pass', 'O', 'Copy Code'],
  ['pass', 'S', 'Show'],
  ['pass', 'N', 'New Entry'],
  ['pass', 'E', 'Edit'],
  ['tailscale', '↵', 'Copy Address'],
  ['tailscale', 'S', 'Send a File'],
  ['tailscale', 'T', 'Turn Tailscale Off or On'],
  ['accounts', '↵', 'Use'],
  ['accounts', 'R', 'Fetch Again'],
  ['dns', 'Space', 'Kid Mode'],
  ['dns', '1-5', 'Flip a Category'],
  ['dns', 'O', 'Open for 30 Minutes'],
  ['dns', '⇧ O', 'Open for 2 Hours'],
  ['dns', 'A', 'Allow a Site'],
  ['dns', 'N', 'Add a Device'],
  ['goals', '↵', 'Fold or Unfold'],
  ['goals', 'Space', 'Tick'],
  ['goals', 'N', 'New Goal'],
  ['goals', 'T', 'New Task'],
  ['goals', '⇧ J / K', 'Reorder'],
  ['goals', 'D', 'Delete'],
].map(([surface, key, title]) => ({ title, key, group: 'IN SURFACES', surface }));

// How a caption names each surface in IN SURFACES.
const SURFACE_NAMES = { shared: 'Every Surface', launcher: 'Launcher', control: 'Control', notifications: 'Notifications', pass: 'Pass', tailscale: 'Tailscale', accounts: 'Accounts', dns: 'DNS', goals: 'Goals' };

// IN SURFACES rows with a caption row before each surface's first row, so a key reads with the surface it belongs to.
function captioned(rows) {
  const out = [];
  rows.forEach((r, i) => {
    if (i === 0 || rows[i - 1].surface !== r.surface) out.push({ caption: SURFACE_NAMES[r.surface], title: SURFACE_NAMES[r.surface], key: '', group: r.group, surface: r.surface });
    out.push(r);
  });
  return out;
}

export function groupRowsSix(rows) {
  return GROUPS_SIX.map((name) => {
    const own = rows.filter((r) => r.group === name);
    return { name, rows: name === 'IN SURFACES' ? captioned(own) : own };
  });
}

export function columnsOfSix(groups) {
  return groups.map((g) => [g]);
}

export function filterRows(rows, query) {
  const q = query.toLowerCase();
  return rows.filter((r) => r.title.toLowerCase().includes(q) || r.key.toLowerCase().includes(q));
}

// A row's key as its keys: the / between a pair, as in J / K, is dropped; a / with no key after it is the key itself, as in Mod /.
export function chipsOf(key) {
  const parts = key.split(' ').filter((p) => p);
  return parts.filter((p, i) => p !== '/' || i === 0 || i === parts.length - 1);
}
