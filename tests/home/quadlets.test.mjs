// The dev databases and mailpit start on a client's first connect, and systemd holds that connect until podman calls the container healthy.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = new URL('../../home/dot_config/containers/systemd/', import.meta.url).pathname;
const quadlets = readdirSync(dir).filter((f) => f.endsWith('.container'));
const key = (text, k) => text.match(new RegExp(`^${k}=(.*)$`, 'm'))?.[1];

// The regular check first runs a whole HealthInterval in, past PDO's 30 s connect timeout, so a startup check polls each second until the first pass.
test('each socket-started container is called healthy within a second of its check first passing', () => {
  assert.deepEqual(quadlets.sort(), ['mailpit.container', 'mysql84.container', 'postgres18.container', 'redis7.container']);
  for (const f of quadlets) {
    const text = readFileSync(join(dir, f), 'utf8');
    assert.equal(key(text, 'Notify'), 'healthy', f);
    assert.equal(key(text, 'HealthStartupCmd'), key(text, 'HealthCmd'), f);
    assert.equal(key(text, 'HealthStartupInterval'), '1s', f);
  }
});
