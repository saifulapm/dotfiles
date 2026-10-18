// Text for the top margins and the island clock. Names are spelled out here rather than
// taken from toLocale*, so QML and node agree whatever the locale.

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export const pad2 = (n) => String(n).padStart(2, '0');

export const dateText = (d) => `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;

export const clockText = (d) => `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;

export const msToNextMinute = (d) => 60000 - (d.getSeconds() * 1000 + d.getMilliseconds());

const hasWindow = (v) => v.app !== null || v.title !== null;

// `qs ipc call margins state`: the canonical text, whatever the theme draws on screen.
export function marginState(view, now) {
  const workspace = pad2(view.idx);
  const app = view.app ?? '';
  const title = view.title ?? '';
  const date = dateText(now);
  return {
    left: { workspace, app, title, text: hasWindow(view) ? `${workspace} · ${app} — ${title}` : workspace },
    right: { date, text: date },
  };
}

// What follows the bold workspace number on screen.
export const screenTail = (view) => (hasWindow(view) ? ` — ${view.app ?? ''} · ${view.title ?? ''}` : '');
