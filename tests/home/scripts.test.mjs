// A script chezmoi runs on every apply makes it rewrite its state db, so a second dots install is no longer a no-op (tests/install/run.sh).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

const dir = new URL('../../home/.chezmoiscripts/', import.meta.url).pathname;

test('every apply script is run_onchange_, keyed on what changes it', () => {
  assert.deepEqual(readdirSync(dir).filter((f) => !/^run_onchange_(before|after)_/.test(f)), []);
});

// pi's settings script says which apply step writes each extension it names, so every step it names must exist.
test('every apply script pi\'s settings script names exists', () => {
  const text = readFileSync(new URL('../../home/dot_pi/agent/modify_settings.json', import.meta.url), 'utf8');
  const named = [...text.matchAll(/\brun_\w+[-\w]*/g)].map((m) => m[0]);
  assert.ok(named.length >= 3, named.join());
  const scripts = readdirSync(dir);
  assert.deepEqual(named.filter((n) => !scripts.some((f) => f.startsWith(`${n}.`))), []);
});
