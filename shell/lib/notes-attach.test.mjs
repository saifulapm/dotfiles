import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { symlinkSync, mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, truncateSync, writeFileSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const script = new URL('../../bin/dots-notes-attach', import.meta.url).pathname;
const sha = (b) => createHash('sha256').update(b).digest('hex');
const PNG = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082', 'hex');
const OVER = 26 * 1024 * 1024;

// A fake wl-paste serving types and bytes from files in the temp dir, so no test reads a real clipboard.
function rig(t) {
  const root = mkdtempSync(join(tmpdir(), 'notes-attach-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bin = join(root, 'bin');
  const clip = join(root, 'clip');
  const out = join(root, 'out');
  for (const d of [bin, clip, out]) mkdirSync(d);
  writeFileSync(join(bin, 'wl-paste'), `#!/bin/sh
[ -e "${clip}/fail" ] && exit 1
if [ "$1" = "--list-types" ]; then cat "${clip}/types"; exit 0; fi
exec cat "${clip}/$(echo "$2" | tr / _)"
`);
  chmodSync(join(bin, 'wl-paste'), 0o755);
  const run = () => {
    const r = spawnSync(script, [out], {
      encoding: 'utf8', maxBuffer: 1 << 20,
      env: Object.assign({}, process.env, { WAYLAND_DISPLAY: '', PATH: bin + ':' + process.env.PATH }),
    });
    assert.equal(r.status, 0, r.stderr);
    return JSON.parse(r.stdout);
  };
  const offer = (types, files) => {
    writeFileSync(join(clip, 'types'), types.join('\n') + '\n');
    for (const [type, data] of Object.entries(files)) writeFileSync(join(clip, type.replace('/', '_')), data);
  };
  return { root, clip, out, run, offer };
}

test('a pasted png is stored under its sha256', (t) => {
  const c = rig(t);
  c.offer(['text/plain', 'image/png'], { 'image/png': PNG });
  assert.deepEqual(c.run(), [{ sha256: sha(PNG), name: 'pasted.png', mime: 'image/png', size: PNG.length }]);
  assert.deepEqual(readdirSync(c.out), [sha(PNG) + '.png']);
  assert.equal(sha(readFileSync(join(c.out, sha(PNG) + '.png'))), sha(PNG));
});

test('an image over 25 MB is refused and leaves nothing behind', (t) => {
  const c = rig(t);
  c.offer(['image/png'], { 'image/png': Buffer.alloc(OVER) });
  assert.deepEqual(c.run(), [{ refused: 'Attachment over 25 MB', name: 'pasted.png' }]);
  // One byte over is still over, though it fits the read's buffer.
  c.offer(['image/png'], { 'image/png': Buffer.alloc(25 * 1024 * 1024 + 1) });
  assert.deepEqual(c.run(), [{ refused: 'Attachment over 25 MB', name: 'pasted.png' }]);
  assert.deepEqual(readdirSync(c.out), []);
});

test('copied files are attached or refused in list order', (t) => {
  const c = rig(t);
  const small = join(c.root, 'my pic.jpg');
  const big = join(c.root, 'big.bin');
  writeFileSync(small, 'jpegbytes');
  writeFileSync(big, '');
  truncateSync(big, OVER);
  const list = ['# comment', 'file://' + small.replace(/ /g, '%20') + '\r', 'file://' + big + '\r', 'https://example.com/x', ''].join('\n');
  c.offer(['text/uri-list', 'image/png'], { 'text/uri-list': list, 'image/png': PNG });
  assert.deepEqual(c.run(), [
    { sha256: sha('jpegbytes'), name: 'my pic.jpg', mime: 'image/jpeg', size: 9 },
    { refused: 'Attachment over 25 MB', name: 'big.bin' },
  ]);
  assert.deepEqual(readdirSync(c.out), [sha('jpegbytes') + '.jpg']);
});

test('text only or a failing wl-paste prints an empty array', (t) => {
  const c = rig(t);
  c.offer(['text/plain'], {});
  assert.deepEqual(c.run(), []);
  writeFileSync(join(c.clip, 'fail'), '');
  assert.deepEqual(c.run(), []);
  assert.deepEqual(readdirSync(c.out), []);
});

test('attaching the same png twice keeps one file and the same hash', (t) => {
  const c = rig(t);
  c.offer(['image/png'], { 'image/png': PNG });
  assert.deepEqual(c.run(), c.run());
  assert.deepEqual(readdirSync(c.out), [sha(PNG) + '.png']);
});

test('a uri-list naming a /proc, /sys or /dev file, directly or through a symlink, attaches nothing', (t) => {
  const c = rig(t);
  symlinkSync('/proc/self/environ', join(c.root, 'innocent.txt'));
  c.offer(['text/uri-list'], { 'text/uri-list': ['file:///proc/cpuinfo', 'file:///sys/kernel/uevent_seqnum', 'file://' + join(c.root, 'innocent.txt')].join('\n') });
  assert.deepEqual(c.run(), []);
  assert.deepEqual(readdirSync(c.out), []);
});
