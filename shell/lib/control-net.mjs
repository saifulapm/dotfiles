// Control's Bluetooth and Wi-Fi row order and text; an order is a list of indices, so the section maps rows back to its devices.
import { line } from './voice.mjs';
import { BIDI, CONTROL } from './clean.mjs';

const btRank = (d) => (d.connected ? 0 : d.paired ? 1 : 2);
const wifiRank = (n) => (n.connected ? 0 : n.known ? 1 : 2);

// New devices list only while a scan runs; a nameless one sorts after the named ones beside it, by address. Ties break on name or signal, since QML's sort is not promised to be stable.
export function btOrder(devs, discovering) {
  const key = (d) => [btRank(d), d.name ? 0 : 1, d.name || d.address || ''];
  const cmp = (a, b) => {
    const [ka, kb] = [key(devs[a]), key(devs[b])];
    return ka[0] - kb[0] || ka[1] - kb[1] || ka[2].localeCompare(kb[2]);
  };
  return devs.map((d, i) => i).filter((i) => discovering || btRank(devs[i]) < 2).sort(cmp);
}

// A headset sends its own name and battery, so the name is one line without controls, and a percentage past 0-100 is not drawn.
export function btRow(dev) {
  const percent = Math.round(dev.battery * 100);
  const battery = dev.connected && dev.batteryAvailable && percent >= 0 && percent <= 100 ? ' · ' + percent + '%' : '';
  const trusted = dev.paired && dev.trusted ? ' · trusted' : '';
  return { title: line((dev.name || '').replace(CONTROL, ' ')) || dev.address, detail: (dev.connected ? 'connected' : dev.paired ? 'paired' : 'new') + trusted + battery };
}

// A Bluetooth page row as board 4 draws it: a glyph by the device's kind, Connected with its battery, Paired or New, and a check while connected.
export function btLook(dev) {
  const icon = dev.icon || '';
  const glyph = /audio|head/.test(icon) ? 0xf02cb : /keyboard/.test(icon) ? 0xf030c : /mouse/.test(icon) ? 0xf037d : /phone/.test(icon) ? 0xf011c : 0xf00af;
  const percent = Math.round(dev.battery * 100);
  const battery = dev.connected && dev.batteryAvailable && percent >= 0 && percent <= 100 ? ' · ' + percent + '%' : '';
  return {
    glyph: String.fromCodePoint(glyph),
    sub: (dev.connected ? 'Connected' : dev.paired ? 'Paired' : 'New') + battery,
    mark: dev.connected ? String.fromCodePoint(0xf012c) : '',
    markTone: 'accent',
  };
}

// What the Bluetooth page says in place of its rows when it has none to list: no adapter, or one turned off.
export function btEmpty(a) {
  if (!a.adapter) return 'No Bluetooth';
  if (!a.enabled) return 'Bluetooth is off';
  return '';
}

// With the adapter off its other keys do nothing, so the hint offers only o.
export function btHint(a) {
  if (!a.adapter) return 'No Bluetooth';
  if (!a.enabled) return 'Bluetooth off · o turn on';
  return `↵ connect · s ${a.discovering ? 'stop' : 'scan'} · t trust · p pair · d forget · o off`;
}

export function wifiOrder(nets) {
  return nets.map((n, i) => i).sort((a, b) => wifiRank(nets[a]) - wifiRank(nets[b]) || nets[b].signalStrength - nets[a].signalStrength);
}

// A Wi-Fi page row as board 4 draws it: a signal glyph by strength, what it is, and a check when joined or a lock when it asks a password.
export function wifiLook(net) {
  const pct = Math.round(net.signalStrength * 100);
  const glyph = String.fromCodePoint(pct >= 75 ? 0xf0928 : pct >= 50 ? 0xf0925 : pct >= 25 ? 0xf0922 : 0xf091f);
  if (net.connected) return { glyph, sub: `Connected · ${pct}%`, mark: String.fromCodePoint(0xf012c), markTone: 'accent' };
  if (net.known) return { glyph, sub: 'Saved', mark: '', markTone: 'muted' };
  if (net.secured) return { glyph, sub: 'Secured', mark: String.fromCodePoint(0xf033e), markTone: 'muted' };
  return { glyph, sub: 'Open', mark: '', markTone: 'muted' };
}

// A network names itself, so its SSID draws as one plain line, as a Bluetooth name does.
export function wifiRow(net) {
  return { title: line((net.name || '').replace(CONTROL, ' ').replace(BIDI, '')), detail: net.connected ? 'connected' : net.known ? 'known' : Math.round(net.signalStrength * 100) + '%' };
}
