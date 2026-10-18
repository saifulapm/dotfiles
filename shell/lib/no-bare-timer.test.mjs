import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// The shell is event driven: the only timer allowed is a Tick, which State counts for `status`.
const shell = new URL('..', import.meta.url).pathname;

test('no .qml under shell/ but Tick.qml declares a Timer', () => {
  const bare = readdirSync(shell, { recursive: true })
    .filter((f) => f.endsWith('.qml') && f !== 'Tick.qml')
    .filter((f) => /\bTimer\s*\{/.test(readFileSync(join(shell, f), 'utf8')));
  assert.deepEqual(bare, []);
});
