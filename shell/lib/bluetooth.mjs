// Pure pieces of the island's Bluetooth states, kept here so node can test them.
import { deviceName } from './bt-pairing.mjs';

// The paired devices that went from off to on since seen, each device's last connected by address; one first seen connected, as when the shell or bluetoothd starts, never counts (9Q4YY211).
export function newlyConnected(seen, devices) {
  const next = {};
  const connected = [];
  for (const d of devices) {
    next[d.address] = d.connected;
    if (d.connected && d.paired && seen[d.address] === false) connected.push(d.address);
  }
  return { seen: next, connected };
}

// A device that reports no battery drops the battery part (7NVWC788).
export const connectText = (c) => `${deviceName(c.name, c.address)} connected${c.battery === null ? '' : ` · ${Math.round(c.battery * 100)}%`}`;
