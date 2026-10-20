import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// dots-call reaches only the handlers State registers, so a plain IpcHandler would answer qs ipc and never the socket niri's binds use.
const shell = new URL('..', import.meta.url).pathname;

test('no .qml under shell/ but Ipc.qml and State.qml declares a plain IpcHandler', () => {
  const plain = readdirSync(shell, { recursive: true })
    .filter((f) => f.endsWith('.qml') && f !== 'Ipc.qml' && f !== 'State.qml')
    .filter((f) => /(^|\s)IpcHandler\s*\{/m.test(readFileSync(join(shell, f), 'utf8')));
  assert.deepEqual(plain, []);
});
