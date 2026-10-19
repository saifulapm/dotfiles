// Day and month names are spelled out, not taken from toLocale*, so QML and node agree in any locale.

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export const pad2 = (n) => String(n).padStart(2, '0');

export const dateText = (d) => `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;

export const clockText = (d) => `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;

export const msToNextMinute = (d) => 60000 - (d.getSeconds() * 1000 + d.getMilliseconds());

const hasWindow = (v) => v.app !== null || v.title !== null;

// `qs ipc call margins state`: the canonical text, whatever the theme draws on screen.
export function marginState(view, now, right) {
  const workspace = pad2(view.idx);
  const app = view.app ?? '';
  const title = view.title ?? '';
  const date = dateText(now);
  return {
    left: { workspace, app, title, text: hasWindow(view) ? `${workspace} · ${app} — ${title}` : workspace },
    right: { sync: right.sync, goal: right.goal, wifi: right.wifi, battery: right.battery, date, text: [right.sync, right.goal, right.wifi, right.battery, date].filter((p) => p).join('  ') },
  };
}

// Quickshell's UPower gives the percentage as 0 to 1.
export const batteryText = (fraction, charging) => `${Math.round(fraction * 100)}%${charging ? ' charging' : ''}`;

// Each device is { wifi, connected }; no Wi-Fi device means no word at all.
export function wifiText(devices) {
  const wifi = devices.filter((d) => d.wifi);
  if (wifi.length === 0) return '';
  return wifi.some((d) => d.connected) ? 'wifi' : 'no wifi';
}
