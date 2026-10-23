// Control's Bluetooth and Wi-Fi row order and text; an order is a list of indices, so the section maps rows back to its devices.
const btRank = (d) => (d.connected ? 0 : d.paired ? 1 : 2);
const wifiRank = (n) => (n.connected ? 0 : n.known ? 1 : 2);

// Ties break on name or signal, since QML's sort is not promised to be stable.
export function btOrder(devs) {
  return devs.map((d, i) => i).sort((a, b) => btRank(devs[a]) - btRank(devs[b]) || devs[a].name.localeCompare(devs[b].name));
}

export function btRow(dev) {
  const battery = dev.connected && dev.batteryAvailable ? ' · ' + Math.round(dev.battery * 100) + '%' : '';
  return { title: dev.name, detail: (dev.connected ? 'connected' : dev.paired ? 'paired' : 'new') + battery };
}

export function wifiOrder(nets) {
  return nets.map((n, i) => i).sort((a, b) => wifiRank(nets[a]) - wifiRank(nets[b]) || nets[b].signalStrength - nets[a].signalStrength);
}

export function wifiRow(net) {
  return { title: net.name, detail: net.connected ? 'connected' : net.known ? 'known' : Math.round(net.signalStrength * 100) + '%' };
}
