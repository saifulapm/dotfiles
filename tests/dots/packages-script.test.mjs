// The packages step against stub rpm, dnf and sudo, on a scratch home: every declared package reads as installed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_before_00-packages.sh.tmpl'), 'utf8');

// remi-release answers with $REMI; everything else is installed.
const RPM = `#!/bin/sh
[ "$1" = -E ] && { echo 44; exit 0; }
for a; do last=$a; done
[ "$last" = remi-release ] && exit "$REMI"
exit 0
`;

function apply({ remi }) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-packages-')));
  mkdirSync(join(home, 'stubs'));
  writeFileSync(join(home, 'stubs/rpm'), RPM, { mode: 0o755 });
  writeFileSync(join(home, 'stubs/dnf'), '#!/bin/sh\necho "$*" >> "$HOME/dnf.log"\n', { mode: 0o755 });
  writeFileSync(join(home, 'stubs/sudo'), '#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n', { mode: 0o755 });
  const env = {
    PATH: `${home}/stubs:/usr/bin:/bin`, HOME: home, REMI: remi ? '0' : '1',
    XDG_CONFIG_HOME: join(home, '.config'), XDG_DATA_HOME: join(home, '.local/share'), XDG_CACHE_HOME: join(home, '.cache'),
  };
  const rendered = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: script, encoding: 'utf8', env });
  assert.equal(rendered.status, 0, rendered.stderr);
  const r = spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env });
  const log = join(home, 'dnf.log');
  return { r, dnf: existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n') : [] };
}

test('a machine with Remi loses its PHP collections and its repo', () => {
  const { r, dnf } = apply({ remi: true });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(dnf.filter((l) => /\bremove\b/.test(l)), ["-y -q remove remi-release php82* php83* php84*"]);
});

test('a machine without Remi removes nothing', () => {
  const { r, dnf } = apply({ remi: false });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(dnf.filter((l) => /\bremove\b/.test(l)), []);
});
