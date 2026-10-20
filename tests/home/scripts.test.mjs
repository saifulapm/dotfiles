// A script chezmoi runs on every apply makes it rewrite its state db, so a second dots install is no longer a no-op (tests/install/run.sh).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';

const dir = new URL('../../home/.chezmoiscripts/', import.meta.url).pathname;

test('every apply script is run_onchange_, keyed on what changes it', () => {
  assert.deepEqual(readdirSync(dir).filter((f) => !/^run_onchange_(before|after)_/.test(f)), []);
});
