// Pure pieces of Control's Power, Display and Route sections.

import { clockText } from './margins.mjs';

// brightnessctl -m -l prints device,class,current,percent,max per line.
export function backlights(text) {
  return text
    .split('\n')
    .map((l) => l.split(','))
    .filter((f) => f.length >= 5)
    .map((f) => ({ device: f[0], percent: parseInt(f[3]) }));
}

// ddcutil detect --terse prints a "Display N" block per external screen, its Monitor line as mfg:model:serial.
export function ddcDisplays(text) {
  return text
    .split(/\n\s*\n/)
    .map((block) => ({ n: block.match(/^Display (\d+)/), model: block.match(/Monitor:\s*[^:\n]*:([^:\n]*)/) }))
    .filter((b) => b.n)
    .map((b) => ({ display: parseInt(b.n[1]), name: b.model ? b.model[1].trim() : 'Display ' + b.n[1] }));
}

// workflow route prints `route: phone` or `route: device (<machine>)`.
export function routeOf(text) {
  const m = text.match(/^route: (phone|device)\b/m);
  return m ? m[1] : '';
}

export const ACTIONS = [
  { id: 'lock', title: 'Lock', confirm: false },
  { id: 'logout', title: 'Log out', confirm: true },
  { id: 'reboot', title: 'Reboot', confirm: true },
  { id: 'poweroff', title: 'Power off', confirm: true },
];

const COMMANDS = {
  lock: ['qs', 'ipc', 'call', 'lock', 'lock'],
  logout: ['niri', 'msg', 'action', 'quit', '--skip-confirmation'],
  reboot: ['systemctl', 'reboot'],
  poweroff: ['systemctl', 'poweroff'],
};

export function actionCommand(id) {
  return COMMANDS[id] || null;
}

// bin/dots sync writes { <unit>: { ok, lastRun, lastOk, error } }; a missing or broken file is no rounds yet.
export function parseSync(text) {
  try {
    const units = JSON.parse(text);
    return units && typeof units === 'object' && !Array.isArray(units) ? units : {};
  } catch (e) {
    return {};
  }
}

export const syncFailing = (units) => Object.keys(units).some((k) => units[k].ok === false);

// Control's detail text has no width of its own, so a long error is cut to 60 characters on screen.
const cut = (s) => (s.length > 60 ? s.slice(0, 59) + '…' : s);

export function syncRows(units) {
  const names = Object.keys(units);
  if (names.length === 0) return [{ title: 'Sync', detail: 'no rounds yet' }];
  const failing = names.filter((k) => units[k].ok === false);
  if (failing.length === 0) {
    const newest = Math.max.apply(null, names.map((k) => units[k].lastOk));
    return [{ title: 'Sync', detail: 'ok · ' + clockText(new Date(newest)) }];
  }
  return [{ title: 'Sync', detail: failing.length + ' failing' }].concat(failing.map((k) => ({ title: k, detail: cut(String(units[k].error)) })));
}
