// The office HomePod's pieces exist on the mini and render to nothing on every other machine.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');
const PIN = 'home/.chezmoiscripts/run_onchange_after_29-pin-cliairplay.sh.tmpl';
const FIREWALL = 'home/.chezmoiscripts/run_onchange_after_46-homepod.sh.tmpl';

// The template rendered as chezmoi would on the named machine, from the given source dir.
function render(file, machine, source = repo) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'homepod-render-')));
  const config = join(root, 'chezmoi.toml');
  writeFileSync(config, `[data]\n    machine = "${machine}"\n`);
  const r = spawnSync('chezmoi', ['--config', config, '--source', source, 'execute-template'], {
    input: readFileSync(join(source, file), 'utf8'),
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: root },
  });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
}

test('cliairplay is pinned to a release with an aarch64 sha256 and installs only on the mini', () => {
  const pin = read('versions.toml').match(/\[\[pin\]\]\nname = "cliairplay"\n[^[]*/)?.[0];
  assert.ok(pin, 'versions.toml has a cliairplay pin');
  assert.match(pin, /^version = "\d+\.\d+\.\d+"$/m);
  assert.match(pin, /^url = "https:\/\/github\.com\/music-assistant\/airplay-cli\/releases\/download\/v\{version\}\/cliairplay-linux-aarch64"$/m);
  assert.match(pin, /^sha256 = "[0-9a-f]{64}"$/m);
  assert.doesNotMatch(pin, /^(check|runs) = /m, 'the install container is no mini, so it has nothing to check');
  for (const machine of ['macbook-m2', 'nuc']) assert.equal(render(PIN, machine).trim(), '', machine);
  assert.match(render(PIN, 'mac-mini-m2'), /^pin_name="cliairplay"$/m);
});

test('on the mini the pin installs the checked binary as ~/.local/bin/cliairplay', () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'homepod-pin-')));
  mkdirSync(join(root, 'home/.chezmoitemplates'), { recursive: true });
  mkdirSync(join(root, 'home/.chezmoiscripts'), { recursive: true });
  for (const f of ['lib.sh', 'pin.sh']) copyFileSync(join(repo, 'home/.chezmoitemplates', f), join(root, 'home/.chezmoitemplates', f));
  copyFileSync(join(repo, PIN), join(root, PIN));
  writeFileSync(join(root, '.chezmoiroot'), 'home\n');
  const binary = '#!/bin/sh\necho cliairplay\n';
  writeFileSync(join(root, 'cliairplay-linux-aarch64'), binary);
  const sum = createHash('sha256').update(binary).digest('hex');
  writeFileSync(
    join(root, 'versions.toml'),
    `[[pin]]\nname = "cliairplay"\nversion = "0.5.9"\nrepo = "x/cliairplay"\nurl = "file://${root}/cliairplay-linux-aarch64"\nsha256 = "${sum}"\n`,
  );
  const r = spawnSync('bash', ['-c', render(PIN, 'mac-mini-m2', root)], { encoding: 'utf8', env: { PATH: process.env.PATH, HOME: root } });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /^dots: pin cliairplay 0\.5\.9$/m);
  const installed = join(root, '.local/bin/cliairplay');
  assert.equal(readFileSync(installed, 'utf8'), binary);
  assert.equal(statSync(installed).mode & 0o777, 0o755);
});

// The firewall script run on the mini with sudo and firewall-cmd stubbed; state is the exit status firewall-cmd --state gives.
function firewall(state) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'homepod-fw-')));
  const bin = join(root, 'bin');
  mkdirSync(bin);
  const log = join(root, 'calls');
  writeFileSync(join(bin, 'sudo'), `#!/bin/bash\n[[ $1 == -n ]] && shift\necho "sudo $*" >>${log}\nexec "$@"\n`, { mode: 0o755 });
  writeFileSync(join(bin, 'firewall-cmd'), `#!/bin/bash\n[[ $1 == --state ]] && exit ${state}\nexit 0\n`, { mode: 0o755 });
  const r = spawnSync('bash', ['-c', render(FIREWALL, 'mac-mini-m2')], { encoding: 'utf8', env: { PATH: `${bin}:${process.env.PATH}`, HOME: root } });
  assert.equal(r.status, 0, r.stderr);
  return spawnSync('cat', [log], { encoding: 'utf8' }).stdout;
}

test("the mini's firewalld opens UDP 319 and 320 for the HomePod's PTP clock, now and after a reboot", () => {
  assert.equal(
    firewall(0),
    [
      'sudo firewall-cmd --state',
      'sudo firewall-cmd -q --add-port=319/udp --add-port=320/udp',
      'sudo firewall-cmd -q --permanent --add-port=319/udp --add-port=320/udp',
      '',
    ].join('\n'),
  );
  assert.equal(firewall(252), 'sudo firewall-cmd --state\n', 'a machine without firewalld, as the install container, opens nothing');
  for (const machine of ['macbook-m2', 'nuc']) assert.equal(render(FIREWALL, machine).trim(), '', machine);
});
