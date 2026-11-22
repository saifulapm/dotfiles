// Day and month names are spelled out, not taken from toLocale*, so QML and node agree in any locale.

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export const pad2 = (n) => String(n).padStart(2, '0');

export const dateText = (d) => `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;

export const clockText = (d) => `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;

export const msToNextMinute = (d) => 60000 - (d.getSeconds() * 1000 + d.getMilliseconds());

// Quickshell's UPower gives the percentage as 0 to 1.
export const batteryText = (fraction, charging) => `${Math.round(fraction * 100)}%${charging ? ' charging' : ''}`;
