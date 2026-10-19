import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// bin/dots-qs picks the renderer from the render node's kernel driver, then runs qs; a fake qs prints what it got.
const dotsQs = new URL('../../bin/dots-qs', import.meta.url).pathname;

function run(t, driver) {
  const dir = mkdtempSync(join(tmpdir(), 'dots-qs-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  writeFileSync(join(dir, 'bin/qs'), '#!/bin/sh\necho "backend=$QSG_RHI_BACKEND select=$VK_LOADER_DRIVERS_SELECT args=$*"\n');
  chmodSync(join(dir, 'bin/qs'), 0o755);
  const node = join(dir, 'renderD128');
  mkdirSync(join(node, 'device'), { recursive: true });
  if (driver) symlinkSync(`../../../bus/platform/drivers/${driver}`, join(node, 'device/driver'));
  const env = { ...process.env, PATH: `${join(dir, 'bin')}:${process.env.PATH}`, DOTS_RENDER_NODE: node };
  delete env.QSG_RHI_BACKEND;
  delete env.VK_LOADER_DRIVERS_SELECT;
  const r = spawnSync(dotsQs, ['-p', 'x'], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout.trim();
}

test("an Apple GPU draws with Vulkan through the Asahi driver only", (t) => {
  assert.equal(run(t, 'asahi'), 'backend=vulkan select=asahi_icd* args=-p x');
});

test('an Intel GPU draws with Vulkan through the Intel drivers only', (t) => {
  assert.equal(run(t, 'i915'), 'backend=vulkan select=intel* args=-p x');
  assert.equal(run(t, 'xe'), 'backend=vulkan select=intel* args=-p x');
});

test('an unknown GPU, or none, keeps OpenGL and every Vulkan driver', (t) => {
  assert.equal(run(t, 'nouveau'), 'backend= select= args=-p x');
  assert.equal(run(t, null), 'backend= select= args=-p x');
});
