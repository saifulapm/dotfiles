// Pure pieces of Control's Power, Display and Route sections.

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
