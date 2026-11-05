// Control's sections in Tab order, and the Audio section's arithmetic and row text.
export const SECTIONS = ['audio', 'wifi', 'bluetooth', 'power', 'display', 'route'];
export const TITLES = ['Audio', 'Wi-Fi', 'Bluetooth', 'Power', 'Display', 'Route'];

export function cycle(index, by) {
  const n = SECTIONS.length;
  return (((index + by) % n) + n) % n;
}

// One h or l press is 5 %, kept on whole percents so float drift never shows as 44 %.
export function stepVolume(volume, dir) {
  const pct = Math.round(volume * 100) + dir * 5;
  return Math.max(0, Math.min(100, pct)) / 100;
}

// A wheel event over a level row: each whole notch, 120 of Qt's angle, is one step, up the l key and down the h key; a touchpad's smaller angles add up in rest, so a swipe steps as far as the notches it adds up to.
export function wheelSteps(rest, angle) {
  const total = rest + angle;
  const steps = Math.trunc(total / 120);
  return { steps, rest: total - steps * 120 };
}

export function audioRow(node) {
  const parts = [node.isSink ? 'Output' : 'Input', node.muted ? 'muted' : Math.round(node.volume * 100) + '%'];
  if (node.isDefault) parts.push('default');
  parts.push(...(node.device ?? []));
  return { title: node.description || node.name, detail: parts.join(' · ') };
}
