import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const relayJs = new URL('../../dev/niri-relay.mjs', import.meta.url).pathname;
const dir = mkdtempSync(join(tmpdir(), 'niri-relay-'));
const upPath = join(dir, 'niri.sock');
const relayPath = join(dir, 'relay.sock');
const stopsLog = join(dir, 'stops');
const upstreamCast = { stream_id: 1, session_id: 1, kind: 'WlrScreencopy', target: { Output: { name: 'winit' } }, is_dynamic_target: false, is_active: true, pid: 42, pw_node_id: null };
const fakeCast = { stream_id: 9, session_id: 7, kind: 'PipeWire', target: 'Nothing', is_dynamic_target: false, is_active: true, pid: null, pw_node_id: 55 };
const fakeCast2 = { ...fakeCast, stream_id: 10 };
const upstreamSeen = [];
let upstream, relay;

before(async () => {
  upstream = net.createServer((c) => {
    let buf = '';
    c.on('data', (d) => {
      buf += d;
      const nl = buf.indexOf('\n');
      if (nl < 0) return;
      const line = buf.slice(0, nl);
      buf = '';
      upstreamSeen.push(line);
      if (line === '"Casts"') c.write('{"Ok":{"Casts":[]}}\n');
      else if (line === '"EventStream"') c.write('{"Ok":"Handled"}\n{"CastsChanged":{"casts":' + JSON.stringify([upstreamCast]) + '}}\n{"OverviewOpenedOrClosed":{"is_open":true}}\n');
      else if (line.includes('StopCast')) c.write('{"Err":"no such cast"}\n');
    });
    c.on('error', () => {});
  });
  await new Promise((r) => upstream.listen(upPath, r));
  relay = spawn('node', [relayJs, 'serve', relayPath, upPath, stopsLog], { stdio: 'inherit' });
  for (let i = 0; i < 100 && !existsSync(relayPath); i++) await new Promise((r) => setTimeout(r, 20));
});
after(() => {
  relay.kill();
  upstream.close();
  rmSync(dir, { recursive: true, force: true });
});

// Connects to the relay, sends one line, and collects the lines that come back.
function client(line) {
  const lines = [];
  const waiters = [];
  const sock = net.connect(relayPath);
  let buf = '';
  sock.on('data', (d) => {
    buf += d;
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      lines.push(buf.slice(0, nl));
      buf = buf.slice(nl + 1);
    }
    for (const w of waiters.splice(0)) w();
  });
  sock.on('error', () => {});
  sock.write(line + '\n');
  return {
    lines,
    async next(n) {
      const t = Date.now() + 2000;
      while (lines.length < n) {
        if (Date.now() > t) throw new Error(`only ${lines.length} lines: ${lines.join(' | ')}`);
        await new Promise((r) => { waiters.push(r); setTimeout(r, 50); });
      }
      return lines.slice(0, n);
    },
    close: () => sock.destroy(),
  };
}
const inject = (ev) => client(JSON.stringify({ DevInject: ev })).next(1);

let stream1;

test('a Casts request gets the upstream reply', async () => {
  const c = client('"Casts"');
  assert.deepEqual(await c.next(1), ['{"Ok":{"Casts":[]}}']);
  c.close();
});

test('an event stream gets the upstream lines in order and injected events', async () => {
  stream1 = client('"EventStream"');
  const first = await stream1.next(3);
  assert.equal(first[0], '{"Ok":"Handled"}');
  assert.deepEqual(JSON.parse(first[1]), { CastsChanged: { casts: [upstreamCast] } });
  assert.deepEqual(JSON.parse(first[2]), { OverviewOpenedOrClosed: { is_open: true } });
  assert.deepEqual(await inject({ CastStartedOrChanged: { cast: fakeCast } }), ['{"Ok":"Handled"}']);
  await inject({ CastStartedOrChanged: { cast: fakeCast2 } });
  const got = await stream1.next(5);
  assert.deepEqual(JSON.parse(got[3]), { CastStartedOrChanged: { cast: fakeCast } });
});

test('a later stream starts with the upstream casts plus the fake ones', async () => {
  const c = client('"EventStream"');
  const lines = await c.next(3);
  assert.deepEqual(JSON.parse(lines[1]), { CastsChanged: { casts: [upstreamCast, fakeCast, fakeCast2] } });
  c.close();
});

test('StopCast for a fake session is answered here and ends its streams', async () => {
  const c = client('{"Action":{"StopCast":{"session_id":7}}}');
  assert.deepEqual(await c.next(1), ['{"Ok":"Handled"}']);
  const got = await stream1.next(7);
  assert.deepEqual(got.slice(5).map((l) => JSON.parse(l)), [{ CastStopped: { stream_id: 9 } }, { CastStopped: { stream_id: 10 } }]);
  assert.equal(upstreamSeen.some((l) => l.includes('StopCast')), false);
  assert.equal(readFileSync(stopsLog, 'utf8'), '7\n');
  const later = client('"EventStream"');
  assert.deepEqual(JSON.parse((await later.next(3))[1]), { CastsChanged: { casts: [upstreamCast] } });
  later.close();
});

test('StopCast for a session the relay did not make goes to the upstream', async () => {
  const c = client('{"Action":{"StopCast":{"session_id":1}}}');
  assert.deepEqual(await c.next(1), ['{"Err":"no such cast"}']);
  assert.deepEqual(upstreamSeen.filter((l) => l.includes('StopCast')), ['{"Action":{"StopCast":{"session_id":1}}}']);
  assert.equal(readFileSync(stopsLog, 'utf8'), '7\n1\n');
  stream1.close();
});
