// The pin.sh template against a scratch source whose one pin points at a local file, so no run reaches the network.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const sha = (s) => createHash('sha256').update(s).digest('hex');
const SCRIPT = `#!/bin/bash
{{ template "lib.sh" . }}
{{ template "pin.sh" (dict "chezmoi" .chezmoi "name" "hello") }}
file=$(pin_fetch)
cat "$file"
pin_done
`;

// A source dir holding the repo's lib.sh and pin.sh beside a versions.toml whose hello pin has the given sha256 on every arch.
function source(sum) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'dots-pins-')));
  const templates = join(root, 'home/.chezmoitemplates');
  mkdirSync(templates, { recursive: true });
  for (const f of ['lib.sh', 'pin.sh']) copyFileSync(join(repo, 'home/.chezmoitemplates', f), join(templates, f));
  writeFileSync(join(root, '.chezmoiroot'), 'home\n');
  writeFileSync(join(root, 'hello-1.2.txt'), 'hello pin\n');
  const url = `file://${root}/hello-{version}.txt`;
  writeFileSync(
    join(root, 'versions.toml'),
    `[[pin]]\nname = "hello"\nversion = "1.2"\nrepo = "x/hello"\ncheck = "hello --version"\n` +
      `url.aarch64 = "${url}"\nurl.x86_64 = "${url}"\nsha256.aarch64 = "${sum}"\nsha256.x86_64 = "${sum}"\n`,
  );
  return root;
}

function run(root) {
  const rendered = spawnSync('chezmoi', ['--config', join(root, 'none.toml'), '--source', root, 'execute-template'], {
    input: SCRIPT,
    encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: root },
  });
  assert.equal(rendered.status, 0, rendered.stderr);
  return spawnSync('bash', ['-c', rendered.stdout], { encoding: 'utf8', env: { PATH: process.env.PATH, HOME: root } });
}

test('a pin with the right sha256 is fetched and reported as changed', () => {
  const r = run(source(sha('hello pin\n')));
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, 'hello pin\ndots: pin hello 1.2\n');
});

test('a pin with a wrong sha256 stops the script, naming the pin', () => {
  const r = run(source('0'.repeat(64)));
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /pin hello: sha256/);
  assert.doesNotMatch(r.stdout, /dots: pin hello/);
});

test('every pin in versions.toml has its own script, and every pin script a pin', () => {
  const pins = [...readFileSync(join(repo, 'versions.toml'), 'utf8').matchAll(/^name = "([^"]+)"/gm)].map((m) => m[1]).sort();
  const scripts = readdirSync(join(repo, 'home/.chezmoiscripts'))
    .map((f) => f.match(/^run_onchange_after_2\d-pin-(.+)\.sh\.tmpl$/)?.[1])
    .filter(Boolean)
    .sort();
  assert.deepEqual(scripts, pins);
  for (const name of pins) {
    const [file] = readdirSync(join(repo, 'home/.chezmoiscripts')).filter((f) => f.endsWith(`-pin-${name}.sh.tmpl`));
    assert.match(readFileSync(join(repo, 'home/.chezmoiscripts', file), 'utf8'), new RegExp(`"name" "${name}"`), file);
  }
});
