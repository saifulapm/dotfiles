import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseStatus, offlineText, stateText, tailscaleKeys } from './tailscale.mjs';

const recorded = readFileSync(new URL('../../dev/tailscale-status.json', import.meta.url), 'utf8');
// 2026-10-21 08:00 UTC: fedora was last seen 55 days before, the old Mac mini 42.
const NOW = Date.parse('2026-10-21T08:00:00Z');
const status = (patch) => JSON.stringify(Object.assign(JSON.parse(recorded), patch));

test('the recorded status gives this device and five machines, three online', () => {
  const s = parseStatus(recorded, NOW);
  assert.equal(s.state, 'on');
  assert.deepEqual(s.self, { name: 'macbook', ip: '100.101.7.12', tailnet: 'taila27604.ts.net' });
  assert.equal(s.online, 3);
  assert.deepEqual(
    s.machines.map((m) => [m.name, m.ip, m.online, m.age]),
    [
      ['iphone', '100.95.3.21', true, ''],
      ['mini', '100.72.40.9', true, ''],
      ['nuc', '100.88.14.3', true, ''],
      ['saifuls-mac-mini', '', false, '42d'],
      ['fedora', '', false, '55d'],
    ],
  );
});

test("a machine is named by its MagicDNS label, since the iPhone's host name is localhost, and falls back to the host name", () => {
  const s = parseStatus(status({ Peer: { a: { HostName: 'Lap Top', DNSName: '', TailscaleIPs: ['100.1.2.3'], Online: true } } }), NOW);
  assert.equal(s.machines[0].name, 'Lap Top');
  assert.equal(parseStatus(recorded, NOW).machines[0].name, 'iphone');
});

test('a name the tailnet sends is one line without bidi marks or control characters', () => {
  const s = parseStatus(status({ Peer: { a: { HostName: 'x', DNSName: 'ev‮il\nbox\u001b.taila27604.ts.net.', TailscaleIPs: ['100.1.2.3'], Online: true } } }), NOW);
  assert.equal(s.machines[0].name, 'evil box');
});

test('an offline age reads in days, hours or minutes, and a zero LastSeen reads as nothing', () => {
  const peer = (seen) => parseStatus(status({ Peer: { a: { DNSName: 'a.t.', TailscaleIPs: ['100.1.2.3'], Online: false, LastSeen: seen } } }), NOW).machines[0].age;
  assert.deepEqual([peer('2026-10-21T05:00:00Z'), peer('2026-10-21T07:58:00Z'), peer('2026-10-21T07:59:50Z'), peer('0001-01-01T00:00:00Z'), peer(undefined)], ['3h', '2m', 'now', '', '']);
});

test('the backend state picks what the surface draws instead of an empty list', () => {
  assert.equal(parseStatus(status({ BackendState: 'Stopped' }), NOW).state, 'off');
  assert.equal(parseStatus(status({ BackendState: 'NeedsLogin', Peer: null }), NOW).state, 'loggedOut');
  assert.equal(parseStatus(status({ BackendState: 'NeedsMachineAuth' }), NOW).state, 'loggedOut');
  assert.equal(parseStatus(status({ BackendState: 'Starting' }), NOW).state, 'starting');
  assert.equal(parseStatus('', NOW).state, 'down');
  assert.equal(parseStatus('failed to connect to local tailscaled', NOW).state, 'down');
  assert.deepEqual(parseStatus('', NOW).machines, []);
  // Off keeps the device block, from the status tailscale still reports.
  assert.equal(parseStatus(status({ BackendState: 'Stopped' }), NOW).self.name, 'macbook');
});

test('each state other than on reads one line, and an offline machine its own', () => {
  assert.deepEqual(['off', 'loggedOut', 'down', 'starting'].map(stateText), ['Tailscale is off', 'Tailscale is logged out', 'tailscaled is not running', 'Tailscale is starting']);
  assert.equal(stateText('on'), '');
  assert.equal(offlineText('fedora'), 'fedora is offline');
});

test('the key strip is the board\'s for on and off; a state with no toggle offers only esc', () => {
  const plain = { keys: (k) => k };
  assert.deepEqual(tailscaleKeys(plain, 'on'), [['↵', 'copy ip'], ['s', 'send files'], ['t', 'turn off'], ['esc', '']]);
  assert.deepEqual(tailscaleKeys(plain, 'off'), [['t', 'turn on'], ['esc', '']]);
  assert.deepEqual(tailscaleKeys(plain, 'down'), [['esc', '']]);
});
