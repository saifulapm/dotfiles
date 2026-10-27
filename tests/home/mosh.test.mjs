// mosh: the package, and the firewall script run with stub sudo and firewall-cmd.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const FIREWALL = 'home/.chezmoiscripts/run_onchange_after_49-mosh.sh.tmpl';

test('mosh is declared for every arch with a reason', () => {
  const block = readFileSync(join(repo, 'packages.toml'), 'utf8').split(/^\[\[package\]\]$/m).find((b) => /^name = "mosh"$/m.test(b));
  assert.match(block ?? '', /^arch = "all"$/m);
  assert.match(block, /^why = "\w/m);
});

// The firewall script as chezmoi renders it, run with sudo and firewall-cmd stubbed; state is the exit status firewall-cmd --state gives.
function firewall(state) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'mosh-fw-')));
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

test('firewalld lets only tailnet addresses reach mosh-server\'s UDP 60000-61000, now and after a reboot, and does nothing without firewalld', () => {
  const v4 = 'rule family="ipv4" source address="100.64.0.0/10" port port="60000-61000" protocol="udp" accept';
  const v6 = 'rule family="ipv6" source address="fd7a:115c:a1e0::/48" port port="60000-61000" protocol="udp" accept';
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
