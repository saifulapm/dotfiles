// wayvnc: the config, the template unit run for real with stub binaries, and the firewall script run with stub sudo and firewall-cmd.
import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const units = join(repo, 'home/dot_config/systemd/user');
const unit = readFileSync(join(units, 'wayvnc@.service'), 'utf8');
const FIREWALL = 'home/.chezmoiscripts/run_onchange_after_48-wayvnc.sh.tmpl';
const name = `wayvnc-test-${process.pid}`;
const OUTPUT = 'TEST-9';

// Every Key=value line of the unit, in order.
const lines = (key) => [...unit.matchAll(new RegExp(`^${key}=(.*)$`, 'gm'))].map((m) => m[1]);

let dir;
after(() => {
  spawnSync('systemctl', ['--user', 'stop', name]);
  spawnSync('systemctl', ['--user', 'reset-failed', name]);
  if (dir) rmSync(dir, { recursive: true, force: true });
});

test('the config listens on 127.0.0.1:5900 and sets nothing else', () => {
  assert.equal(readFileSync(join(repo, 'home/dot_config/wayvnc/config'), 'utf8'), 'address=127.0.0.1\nport=5900\n');
});

test('the unit runs wayvnc for one output through wl-uinput-proxy, capped at 256M, and nothing starts it at login', () => {
  // systemd looks a bare name up in its own fixed path, which has no ~/.local/bin, so the pin's binary is named by %h.
  assert.deepEqual(lines('ExecStart'), ['%h/.local/bin/wl-uinput-proxy /usr/bin/wayvnc -r -o %i']);
  assert.deepEqual(lines('ExecStart')[0].split(' ').slice(0, 2).map((w) => w.split('/').at(-1)), ['wl-uinput-proxy', 'wayvnc']);
  assert.deepEqual(lines('MemoryMax'), ['256M']);
  assert.doesNotMatch(unit, /^\[Install\]/m);
  assert.deepEqual(lines('WantedBy'), []);
  for (const d of readdirSync(units).filter((f) => f.endsWith('.wants'))) {
    for (const f of readdirSync(join(units, d))) {
      assert.doesNotMatch(readFileSync(join(units, d, f), 'utf8'), /wayvnc/, `${d}/${f}`);
    }
  }
});

test('starting the unit opens tailscale serve on 5900 and stopping it closes it, after wayvnc got its output', () => {
  dir = realpathSync(mkdtempSync(join(tmpdir(), 'wayvnc-unit-')));
  const log = join(dir, 'log');
  const stub = (bin, body) => {
    const p = join(dir, bin);
    writeFileSync(p, `#!/bin/bash\n${body}\n`, { mode: 0o755 });
    return p;
  };
  const wayvnc = stub('wayvnc', `echo "wayvnc $*" >>${log}\nexec sleep 600`);
  // The real proxy would add uinput devices to this machine's niri.
  const proxy = stub('wl-uinput-proxy', `echo "wl-uinput-proxy $*" >>${log}\nexec "$@"`);
  const timeout = stub('timeout', 'shift\nexec "$@"');
  const tailscale = stub('tailscale', `echo "tailscale $*" >>${log}`);
  const fill = (v) =>
    v.replaceAll('%i', OUTPUT).replace('%h/.local/bin/wl-uinput-proxy', proxy).replace('/usr/bin/wayvnc', wayvnc).replace('/usr/bin/timeout', timeout).replace('/usr/bin/tailscale', tailscale);
  const props = ['ExecStartPost', 'ExecStopPost'].flatMap((k) => lines(k).flatMap((v) => ['-p', `${k}=${fill(v)}`]));
  const argv = fill(lines('ExecStart')[0]).split(/\s+/);
  const up = spawnSync('systemd-run', ['--user', '--unit', name, ...props, '--', ...argv], { encoding: 'utf8' });
  assert.equal(up.status, 0, up.stderr);
  const read = () => (existsSync(log) ? readFileSync(log, 'utf8') : '');
  for (let i = 0; i < 100 && !(read().includes('tailscale serve --bg') && /^wayvnc -r/m.test(read())); i++) spawnSync('sleep', ['0.05']);
  const down = spawnSync('systemctl', ['--user', 'stop', name], { encoding: 'utf8' });
  assert.equal(down.status, 0, down.stderr);
  // wayvnc and ExecStartPost start together, so only the tailscale lines have an order.
  const logged = read().trim().split('\n');
  assert.ok(logged.includes(`wl-uinput-proxy ${wayvnc} -r -o ${OUTPUT}`), logged.join('|'));
  assert.ok(logged.includes(`wayvnc -r -o ${OUTPUT}`), logged.join('|'));
  assert.deepEqual(logged.filter((l) => l.startsWith('tailscale')), [
    'tailscale serve --bg --yes --tcp=5900 tcp://127.0.0.1:5900',
    'tailscale serve --tcp=5900 off',
  ]);
});

// The firewall script as chezmoi renders it, run with sudo and firewall-cmd stubbed; state is the exit status firewall-cmd --state gives.
function firewall(state) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'wayvnc-fw-')));
  const bin = join(root, 'bin');
  mkdirSync(bin);
  const log = join(root, 'calls');
  const config = join(root, 'chezmoi.toml');
  writeFileSync(config, '[data]\n    machine = "nuc"\n');
  const rendered = spawnSync('chezmoi', ['--config', config, '--source', repo, 'execute-template'], {
    input: readFileSync(join(repo, FIREWALL), 'utf8'),
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: root },
  });
  assert.equal(rendered.status, 0, rendered.stderr);
  writeFileSync(join(bin, 'sudo'), `#!/bin/bash\n[[ $1 == -n ]] && shift\necho "sudo $*" >>${log}\nexec "$@"\n`, { mode: 0o755 });
  writeFileSync(join(bin, 'firewall-cmd'), `#!/bin/bash\n[[ $1 == --state ]] && exit ${state}\nexit 0\n`, { mode: 0o755 });
  const r = spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env: { PATH: `${bin}:${process.env.PATH}`, HOME: root } });
  assert.equal(r.status, 0, r.stderr);
  return readFileSync(log, 'utf8');
}

test('firewalld lets only tailnet addresses reach 5900, now and after a reboot, and does nothing without firewalld', () => {
  const v4 = 'rule family="ipv4" source address="100.64.0.0/10" port port="5900" protocol="tcp" accept';
  const v6 = 'rule family="ipv6" source address="fd7a:115c:a1e0::/48" port port="5900" protocol="tcp" accept';
  assert.equal(
    firewall(0),
    [
      'sudo firewall-cmd --state',
      `sudo firewall-cmd -q --add-rich-rule=${v4}`,
      `sudo firewall-cmd -q --permanent --add-rich-rule=${v4}`,
      `sudo firewall-cmd -q --add-rich-rule=${v6}`,
      `sudo firewall-cmd -q --permanent --add-rich-rule=${v6}`,
      '',
    ].join('\n'),
  );
  assert.equal(firewall(252), 'sudo firewall-cmd --state\n');
});
