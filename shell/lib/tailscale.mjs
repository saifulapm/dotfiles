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
    .map((p) => ({ name: nameOf(p), ip: p.Online ? ipv4(p) : '', online: p.Online === true, age: p.Online ? '' : ageOf(p.LastSeen, now), seen: Date.parse(p.LastSeen) || 0 }))
    .sort((a, b) => (a.online !== b.online ? (a.online ? -1 : 1) : a.online ? a.name.localeCompare(b.name) : b.seen - a.seen))
    .map((m) => ({ name: m.name, ip: m.ip, online: m.online, age: m.age }));
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
