// The apply's composer step against a stub composer, on a scratch home that reaches no real config.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_19-composer.sh.tmpl'), 'utf8');

// The stub composer logs its argv and the COMPOSER_HOME it sees, then exits with the code it is given.
const composer = (code) => `#!/bin/sh
echo "$* HOME=$COMPOSER_HOME" >> "$HOME/composer.log"
exit ${code}
`;

function apply({ code }) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-composer-')));
  mkdirSync(join(home, 'stubs'));
  writeFileSync(join(home, 'stubs/composer'), composer(code), { mode: 0o755 });
  const env = {
    PATH: `${home}/stubs:/usr/bin:/bin`,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_DATA_HOME: join(home, '.local/share'),
    XDG_CACHE_HOME: join(home, '.cache'),
    COMPOSER_HOME: join(home, 'elsewhere'),
  };
  const rendered = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: script, encoding: 'utf8', env });
  assert.equal(rendered.status, 0, rendered.stderr);
  const r = spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env });
  const calls = existsSync(join(home, 'composer.log')) ? readFileSync(join(home, 'composer.log'), 'utf8').trim().split('\n') : [];
  return { r, calls, home };
}

test('the step requires the installer and Pint once, in the config composer home', () => {
  const { r, calls, home } = apply({ code: 0 });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(calls, [`global require --no-interaction laravel/installer:^5 laravel/pint:^1 HOME=${home}/.config/composer`]);
});

test('a failing composer fails the step and names it', () => {
  const { r } = apply({ code: 1 });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /composer/);
});
