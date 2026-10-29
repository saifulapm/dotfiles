// Control's Bluetooth and Wi-Fi row order and text; an order is a list of indices, so the section maps rows back to its devices.
import { line } from './voice.mjs';

const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
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

// With the adapter off its other keys do nothing, so the hint offers only o.
export function btHint(a) {
  if (!a.adapter) return 'No Bluetooth';
  if (!a.enabled) return 'Bluetooth off · o turn on';
  return `↵ connect · s ${a.discovering ? 'stop' : 'scan'} · t trust · p pair · d forget · o off`;
}

export function wifiOrder(nets) {
  return nets.map((n, i) => i).sort((a, b) => wifiRank(nets[a]) - wifiRank(nets[b]) || nets[b].signalStrength - nets[a].signalStrength);
}

export function wifiRow(net) {
  return { title: net.name, detail: net.connected ? 'connected' : net.known ? 'known' : Math.round(net.signalStrength * 100) + '%' };
}
