// Tailscale's rows from `tailscale status --json`: this device, the machines with online state, and the backend state the surface draws instead of an empty list.
import { line } from './voice.mjs';

// A machine's name, address and the rest come from the tailnet, so a name is one line with no control characters.
const clean = (s) => line(String(s || '').replace(/[\u0000-\u001f\u007f-\u009f]/g, ' '));
// The MagicDNS label, since the iPhone reports its host name as localhost.
const nameOf = (node) => clean(String(node.DNSName || '').split('.')[0] || node.HostName);
const ipv4 = (node) => (node.TailscaleIPs || []).find((ip) => String(ip).includes('.')) || '';

// How long ago an offline machine was seen; tailscale sends the zero time for a machine that never was.
function ageOf(seen, now) {
  const at = Date.parse(seen);
  if (!seen || Number.isNaN(at) || at <= 0) return '';
  const min = Math.floor((now - at) / 60000);
  if (min < 1) return 'now';
  if (min < 60) return `${min}m`;
  if (min < 1440) return `${Math.floor(min / 60)}h`;
  return `${Math.floor(min / 1440)}d`;
}

const STATES = { Running: 'on', Stopped: 'off', NeedsLogin: 'loggedOut', NeedsMachineAuth: 'loggedOut', Starting: 'starting', NoState: 'starting' };

// Online machines by name, then offline ones most recently seen first; the status lists peers by node key, an order of its own.
export function parseStatus(text, now) {
  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    data = null;
  }
  if (!data || typeof data !== 'object' || !STATES[data.BackendState]) return { state: 'down', self: null, machines: [], online: 0 };
  const self = data.Self ? { name: nameOf(data.Self), ip: ipv4(data.Self), tailnet: clean(data.MagicDNSSuffix || data.CurrentTailnet?.MagicDNSSuffix) } : null;
  const machines = Object.values(data.Peer || {})
    .filter((p) => p && typeof p === 'object')
    .map((p) => ({ name: nameOf(p), ip: p.Online ? ipv4(p) : '', online: p.Online === true, age: p.Online ? '' : ageOf(p.LastSeen, now), phone: /^(iOS|android)$/i.test(p.OS || ''), seen: Date.parse(p.LastSeen) || 0 }))
    .sort((a, b) => (a.online !== b.online ? (a.online ? -1 : 1) : a.online ? a.name.localeCompare(b.name) : b.seen - a.seen))
    .map((m) => ({ name: m.name, ip: m.ip, online: m.online, age: m.age, phone: m.phone }));
  return { state: STATES[data.BackendState], self, machines, online: machines.filter((m) => m.online).length };
}

const LINES = { off: 'Tailscale is off', loggedOut: 'Tailscale is logged out', down: 'tailscaled is not running', starting: 'Tailscale is starting' };
export const stateText = (state) => LINES[state] || '';

export const offlineText = (name) => `${clean(name)} is offline`;

export function tailscaleKeys(look, state) {
  if (state === 'on') return look.keys([['↵', 'copy ip'], ['s', 'send files'], ['t', 'turn off'], ['esc', '']]);
  if (state === 'off') return look.keys([['t', 'turn on'], ['esc', '']]);
  return look.keys([['esc', '']]);
}

// The boards' marks that no token carries: Paper's green square, Artboard's badge dot, online dot, outline grey and badge chip.
const MARKS = { caps: { online: '#3D6B3A' }, plain: { on: '#6C83FF', online: '#1E8E5A', outline: '#8A909B', chip: '#F2F3F6' } };

// How the surface's own parts read under a theme: the ON or OFF badge, a machine's state word and mark, the count, and the one-line states.
export function tailscaleLook(tokens) {
  const c = tokens.color;
  const voice = tokens.type.voice;
  const say = (s) => (voice === 'plain' ? s : s.toUpperCase());
  if (voice === 'plain') {
    const m = MARKS.plain;
    return {
      voice,
      words: say,
      badge: (on) => ({ text: on ? 'ON' : 'OFF', color: on ? '#FFFFFF' : c.muted, fill: on ? c.ink : m.chip, border: 'transparent', dashed: false, radius: 8, dot: { size: 6, fill: on ? m.on : 'transparent', line: on ? 'transparent' : m.outline, radius: 3 } }),
      status: (row) => ({ word: row.online ? 'online' : row.age, dot: row.online ? m.online : 'transparent' }),
      dotLine: m.outline,
      detail: (row) => (row.online ? row.ip : 'offline'),
      count: () => '',
      stateLine: stateText,
    };
  }
  if (voice === 'bracket') {
    return {
      voice,
      words: say,
      badge: (on) => ({ text: on ? '● ON' : '○ OFF', color: on ? c.accent : c.muted, fill: 'transparent', border: on ? c.accent : c.muted, dashed: !on, radius: 0, dot: null }),
      status: (row) => ({ word: row.online ? '● ONLINE' : '○ OFFLINE', dot: null }),
      dotLine: c.muted,
      detail: (row) => (row.online ? row.ip : row.age.toUpperCase()),
      count: (online, offline) => `${online} ONLINE · ${offline} OFFLINE`,
      stateLine: (state) => stateText(state).toUpperCase(),
    };
  }
  return {
    voice,
    words: say,
    badge: (on) => ({ text: on ? 'ON' : 'OFF', color: on ? c.ink : c.muted, fill: 'transparent', border: on ? c.ink : c.muted, dashed: false, radius: 0, dot: { size: 7, fill: on ? MARKS.caps.online : 'transparent', line: on ? 'transparent' : c.muted, radius: 0 } }),
    status: (row) => ({ word: row.online ? 'online' : `offline ${row.age}`.trim(), dot: row.online ? MARKS.caps.online : 'transparent' }),
    dotLine: c.muted,
    detail: (row) => row.ip,
    count: (online) => `${online} ONLINE`,
    stateLine: stateText,
  };
}
