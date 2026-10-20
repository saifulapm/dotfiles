// Every user unit v2 starts or links must ship in home/; a typo in a start line or a link only fails at login, and silently.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const home = new URL('../../home/', import.meta.url).pathname;
const units = join(home, 'dot_config/systemd/user');
// A unit ships as itself, or as a chezmoi template that renders to it.
const shipped = (name) => existsSync(join(units, name)) || existsSync(join(units, name + '.tmpl'));
const unitText = (name) => readFileSync(join(units, existsSync(join(units, name)) ? name : name + '.tmpl'), 'utf8');

test('every unit niri starts at login ships in home/', () => {
  const config = readFileSync(join(home, 'dot_config/niri/config.kdl'), 'utf8');
  const started = [...config.matchAll(/spawn-at-startup "systemctl" "--user" "start" "([^"]+)"/g)].map((m) => m[1]);
  assert.ok(started.length >= 7, `found ${started.length} start lines`);
  assert.deepEqual(started.filter((u) => !shipped(u)), []);
});

test('every .wants link points at a unit that ships, or at a packaged one by absolute path', () => {
  const links = readdirSync(units, { recursive: true }).filter((f) => /\.wants\/symlink_/.test(f));
  assert.ok(links.length > 0);
  const broken = links.filter((f) => {
    const target = readFileSync(join(units, f), 'utf8').trim();
    return target.startsWith('/') ? !target.startsWith('/usr/lib/systemd/user/') : !shipped(target.replace(/^\.\.\//, ''));
  });
  assert.deepEqual(broken, []);
});

test('every timer, path and socket has the service it triggers', () => {
  const triggers = readdirSync(units).filter((f) => /\.(timer|path|socket)(\.tmpl)?$/.test(f)).map((f) => f.replace(/\.tmpl$/, ''));
  const missing = triggers.filter((t) => {
    const named = unitText(t).match(/^Unit=(\S+)/m);
    return !shipped(named ? named[1] : t.replace(/\.(timer|path|socket)$/, '.service'));
  });
  assert.deepEqual(missing, []);
});
