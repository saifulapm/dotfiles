// A relay in front of niri's socket for nested checks: it injects cast events and answers StopCast for casts a check made up, because nested niri cannot start a PipeWire cast.
import net from 'node:net';
import { appendFileSync, rmSync } from 'node:fs';

const OK = '{"Ok":"Handled"}\n';

// Calls onLine for the first line of a socket and hands back any bytes after it.
function firstLine(sock, onLine) {
  let buf = Buffer.alloc(0);
  const onData = (d) => {
    buf = Buffer.concat([buf, d]);
    const nl = buf.indexOf(10);
    if (nl < 0) return;
    sock.off('data', onData);
    sock.pause();
    onLine(buf.subarray(0, nl).toString(), buf.subarray(nl + 1));
  };
  sock.on('data', onData);
}

function serve(listenPath, niriPath, stopsLog) {
  const fakes = new Map(); // stream_id -> cast
  const streams = new Set();
  const broadcast = (ev) => {
    for (const s of streams) s.write(JSON.stringify(ev) + '\n');
  };

  const onInject = (ev) => {
    if (ev.CastStartedOrChanged) fakes.set(ev.CastStartedOrChanged.cast.stream_id, ev.CastStartedOrChanged.cast);
    if (ev.CastStopped) fakes.delete(ev.CastStopped.stream_id);
    broadcast(ev);
  };

  const onStop = (id) => {
    appendFileSync(stopsLog, id + '\n');
    const mine = [...fakes.values()].filter((c) => c.session_id === id);
    for (const c of mine) fakes.delete(c.stream_id);
    for (const c of mine) broadcast({ CastStopped: { stream_id: c.stream_id } });
    return mine.length > 0;
  };

  // niri's own CastsChanged gets the fake casts appended, so a reconnecting shell still sees them.
  const withFakes = (line) => {
    if (!line.startsWith('{"CastsChanged"')) return line;
    try {
      const ev = JSON.parse(line);
      ev.CastsChanged.casts.push(...fakes.values());
      return JSON.stringify(ev);
    } catch {
      return line;
    }
  };

  const server = net.createServer((client) => {
    client.on('error', () => {});
    firstLine(client, (line, rest) => {
      let req;
      try {
        req = JSON.parse(line);
      } catch {
        req = null;
      }
      if (req?.DevInject) {
        onInject(req.DevInject);
        client.end(OK);
        return;
      }
      const stopId = req?.Action?.StopCast?.session_id;
      if (stopId !== undefined && onStop(stopId)) {
        client.end(OK);
        return;
      }
      const up = net.connect(niriPath);
      up.on('error', () => client.destroy());
      client.on('close', () => up.destroy());
      up.on('close', () => client.destroy());
      up.write(line + '\n');
      if (rest.length) up.write(rest);
      if (line === '"EventStream"') {
        let buf = '';
        let first = true;
        up.on('data', (d) => {
          buf += d;
          let nl;
          while ((nl = buf.indexOf('\n')) >= 0) {
            client.write(withFakes(buf.slice(0, nl)) + '\n');
            buf = buf.slice(nl + 1);
            if (first) {
              first = false;
              streams.add(client);
              client.on('close', () => streams.delete(client));
            }
          }
        });
      } else {
        up.pipe(client);
      }
      client.pipe(up);
      client.resume();
    });
  });
  rmSync(listenPath, { force: true });
  server.listen(listenPath);
  for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => process.exit(0));
}

function inject(listenPath, event) {
  const c = net.connect(listenPath);
  c.on('error', (e) => {
    console.error(e.message);
    process.exit(1);
  });
  c.on('data', (d) => {
    process.stdout.write(d);
    c.end();
  });
  c.write(JSON.stringify({ DevInject: JSON.parse(event) }) + '\n');
}

const [mode, ...args] = process.argv.slice(2);
if (mode === 'serve' && args.length === 3) serve(...args);
else if (mode === 'inject' && args.length === 2) inject(...args);
else {
  console.error('usage: niri-relay.mjs serve <listen> <niri> <stops-log> | inject <listen> <event json>');
  process.exit(2);
}
