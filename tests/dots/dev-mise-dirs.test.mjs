import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// A nested check that moves XDG_DATA_HOME or XDG_CACHE_HOME also hides mise's own dirs, whose first call in a fresh cache fetches for seconds (lessons, 2026-11-01); tests/dev/lib.sh's $mise_dirs keeps them.
const dev = new URL('../dev/', import.meta.url).pathname;

test('every tests/dev launch line that moves XDG_DATA_HOME or XDG_CACHE_HOME carries $mise_dirs', () => {
  const bare = [];
  for (const f of readdirSync(dev).filter((f) => f.endsWith('.sh'))) {
    readFileSync(join(dev, f), 'utf8')
      .split('\n')
      .forEach((line, i) => {
        if (/^\s*(env_line|exec_line)=/.test(line) && /XDG_(DATA|CACHE)_HOME=/.test(line) && !line.includes('$mise_dirs')) bare.push(`${f}:${i + 1}`);
      });
  }
  assert.deepEqual(bare, []);
});
