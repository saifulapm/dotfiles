// dots-files-op on scratch folders: copies, moves, names that clash, refusals, symlinks, SIGTERM and a full disk.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync, statSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';

const bin = new URL('../../bin/dots-files-op', import.meta.url).pathname;
const MiB = 1024 * 1024;

function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'files-op-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const dst = join(root, 'dst');
  mkdirSync(dst);
  return { root, dst };
}

const run = (...args) => {
  const r = spawnSync(bin, args, { encoding: 'utf8', timeout: 10000 });
  return { ...r, events: r.stdout.split('\n').filter(Boolean).map((l) => JSON.parse(l)) };
};

// Spawns the command and hands each event to answer(event, child) as it arrives; a run that hangs is killed after 20 s.
function live(cmd, args, answer) {
  const child = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'inherit'] });
  const timer = setTimeout(() => child.kill('SIGKILL'), 20000);
  const events = [];
  createInterface({ input: child.stdout }).on('line', (line) => {
    const event = JSON.parse(line);
    events.push(event);
    answer(event, child);
  });
  return new Promise((resolve) =>
    child.on('close', (status) => {
      clearTimeout(timer);
      resolve({ status, events });
    }),
  );
}

test('copies two files with their bytes and mtime, reporting start, progress, each item and done', (t) => {
  const { root, dst } = scratch(t);
  const a = join(root, 'a.txt');
  const b = join(root, 'b.bin');
  writeFileSync(a, 'alpha\n');
  writeFileSync(b, Buffer.alloc(5000, 7));
  utimesSync(a, 1700000000, 1700000000);
  utimesSync(b, 1600000000, 1600000000);
  const r = run('copy', dst, a, b);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(
    r.events.filter((e) => e.event !== 'progress'),
    [
      { event: 'start', items: 2, bytes: 5006 },
      { event: 'item', index: 0, src: a, dest: join(dst, 'a.txt') },
      { event: 'item', index: 1, src: b, dest: join(dst, 'b.bin') },
      { event: 'done', copied: [0, 1] },
    ],
  );
  assert.equal(r.events[1].event, 'progress');
  const last = r.events.filter((e) => e.event === 'progress').at(-1);
  assert.deepEqual([last.done, last.total], [5006, 5006]);
  assert.equal(readFileSync(join(dst, 'a.txt'), 'utf8'), 'alpha\n');
  assert.deepEqual(readFileSync(join(dst, 'b.bin')), Buffer.alloc(5000, 7));
  assert.equal(statSync(join(dst, 'a.txt')).mtimeMs, 1700000000000);
  assert.equal(statSync(join(dst, 'b.bin')).mtimeMs, 1600000000000);
});

test('moves two files within one filesystem', (t) => {
  const { root, dst } = scratch(t);
  const a = join(root, 'a.txt');
  const b = join(root, 'b.txt');
  writeFileSync(a, 'one');
  writeFileSync(b, 'two');
  const r = run('move', dst, a, b);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.events.at(-1), { event: 'done', copied: [0, 1] });
  assert.equal(existsSync(a), false);
  assert.equal(existsSync(b), false);
  assert.equal(readFileSync(join(dst, 'a.txt'), 'utf8'), 'one');
  assert.equal(readFileSync(join(dst, 'b.txt'), 'utf8'), 'two');
});

test('a name already in the target keeps both, the new one numbered', (t) => {
  const { root, dst } = scratch(t);
  const notes = join(root, 'notes.txt');
  const bashrc = join(root, '.bashrc');
  const folder = join(root, 'v1.2');
  writeFileSync(notes, 'new');
  writeFileSync(bashrc, 'rc');
  mkdirSync(folder);
  writeFileSync(join(folder, 'in.txt'), 'inside');
  writeFileSync(join(dst, 'notes.txt'), 'old');
  writeFileSync(join(dst, '.bashrc'), 'old rc');
  mkdirSync(join(dst, 'v1.2'));
  let r = run('copy', dst, notes);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.events.find((e) => e.event === 'item').dest, join(dst, 'notes (1).txt'));
  r = run('copy', dst, notes, bashrc, folder);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(
    r.events.filter((e) => e.event === 'item').map((e) => e.dest),
    [join(dst, 'notes (2).txt'), join(dst, '.bashrc (1)'), join(dst, 'v1.2 (1)')],
  );
  assert.equal(readFileSync(join(dst, 'notes.txt'), 'utf8'), 'old');
  assert.equal(readFileSync(join(dst, 'notes (1).txt'), 'utf8'), 'new');
  assert.equal(readFileSync(join(dst, '.bashrc'), 'utf8'), 'old rc');
  assert.equal(readFileSync(join(dst, 'v1.2 (1)', 'in.txt'), 'utf8'), 'inside');
  assert.deepEqual(readdirSync(join(dst, 'v1.2')), []);
});

test('a folder copied into itself or its own child is refused and nothing is written', (t) => {
  const { root } = scratch(t);
  const folder = join(root, 'photos');
  mkdirSync(join(folder, 'trip'), { recursive: true });
  writeFileSync(join(folder, 'a.jpg'), 'jpg');
  for (const target of [folder, join(folder, 'trip')]) {
    const r = run('copy', target, folder);
    assert.equal(r.status, 3, r.stderr);
    assert.deepEqual(r.events, [{ event: 'refused', why: 'into-itself', src: folder }]);
  }
  assert.deepEqual(readdirSync(folder, { recursive: true }).sort(), ['a.jpg', 'trip']);
});

test('a symlink is copied as a symlink to the same target, inside a folder too', (t) => {
  const { root, dst } = scratch(t);
  const link = join(root, 'link');
  symlinkSync('../nowhere/file', link);
  const folder = join(root, 'dir');
  mkdirSync(folder);
  symlinkSync('/etc/hostname', join(folder, 'host'));
  const r = run('copy', dst, link, folder);
  assert.equal(r.status, 0, r.stderr);
  assert.ok(lstatSync(join(dst, 'link')).isSymbolicLink());
  assert.equal(readlinkSync(join(dst, 'link')), '../nowhere/file');
  assert.ok(lstatSync(join(dst, 'dir', 'host')).isSymbolicLink());
  assert.equal(readlinkSync(join(dst, 'dir', 'host')), '/etc/hostname');
});

test('SIGTERM during a large copy cancels it and leaves no partial file', async (t) => {
  const { root, dst } = scratch(t);
  const big = join(root, 'big.bin');
  writeFileSync(big, randomBytes(96 * MiB));
  const r = await live(bin, ['copy', dst, big], (e, child) => {
    if (e.event === 'progress' && e.done < e.total) child.kill('SIGTERM');
  });
  assert.equal(r.status, 130);
  assert.deepEqual(r.events.at(-1), { event: 'cancelled', copied: [] });
  assert.equal(existsSync(join(dst, 'big.bin')), false);
});

// The tmpfs lives in the unshare's mount namespace, so this shell runs the deletes and listings the test asks for on stdin, and passes every other line on.
const FULL = `dir=$1 bin=$2 seen=$3; shift 3
mount -t tmpfs -o size=3M tmpfs "$dir" || exit 9
while IFS= read -r line; do
  case $line in
    "rm "*) rm -f -- "$dir/\${line#rm }" ;;
    ls) find "$dir" -mindepth 1 -printf '%P %s\\n' | sort >>"$seen"; echo -- >>"$seen" ;;
    *) printf '%s\\n' "$line" ;;
  esac
done | "$bin" copy "$dir" "$@"
rc=$?
find "$dir" -mindepth 1 -printf '%P %s\\n' | sort >>"$seen"
exit $rc
`;

function fullDisk(t, answer) {
  const { root } = scratch(t);
  const disk = join(root, 'disk');
  mkdirSync(disk);
  const sizes = { 'one.bin': 1, 'two.bin': 1, 'three.bin': 2, 'four.bin': 1 };
  const srcs = Object.entries(sizes).map(([name, n]) => {
    writeFileSync(join(root, name), Buffer.alloc(n * MiB, name.length));
    return join(root, name);
  });
  const seen = join(root, 'seen');
  const done = live('unshare', ['--user', '--map-root-user', '--mount', 'sh', '-c', FULL, 'sh', disk, bin, seen, ...srcs], (e, child) => {
    if (e.event === 'failed') child.stdin.write('ls\n' + answer(e).join('\n') + '\n');
    if (e.event === 'done' || e.event === 'cancelled') child.stdin.end();
  });
  return done.then((r) => ({ ...r, srcs, seen: existsSync(seen) ? readFileSync(seen, 'utf8') : '' }));
}

test('a full disk stops on the third file, removes its partial, and skip goes on to the fourth', async (t) => {
  const r = await fullDisk(t, () => ['skip']);
  assert.equal(r.status, 0);
  assert.deepEqual(r.events.filter((e) => e.event === 'failed'), [
    { event: 'failed', index: 2, src: r.srcs[2], file: r.srcs[2], error: 'No space left on device', copied: [0, 1], pending: [3] },
  ]);
  assert.deepEqual(r.events.at(-1), { event: 'done', copied: [0, 1, 3] });
  assert.equal(r.seen, `one.bin ${MiB}\ntwo.bin ${MiB}\n--\nfour.bin ${MiB}\none.bin ${MiB}\ntwo.bin ${MiB}\n`);
});

test('cancel on a full disk exits 1 and leaves no partial', async (t) => {
  const r = await fullDisk(t, () => ['cancel']);
  assert.equal(r.status, 1);
  assert.deepEqual(r.events.at(-1), { event: 'cancelled', copied: [0, 1] });
  assert.equal(r.seen, `one.bin ${MiB}\ntwo.bin ${MiB}\n--\none.bin ${MiB}\ntwo.bin ${MiB}\n`);
});

// After a copied file is deleted the third fits; the fourth then finds the disk full too, so each failure deletes one more and retries.
test('retry after room is made copies the file that failed', async (t) => {
  const freed = ['one.bin', 'two.bin'];
  const r = await fullDisk(t, () => [`rm ${freed.shift()}`, 'retry']);
  assert.equal(r.status, 0);
  assert.deepEqual(r.events.filter((e) => e.event === 'failed').map((e) => [e.index, e.copied, e.pending]), [
    [2, [0, 1], [3]],
    [3, [0, 1, 2], []],
  ]);
  assert.deepEqual(r.events.at(-1), { event: 'done', copied: [0, 1, 2, 3] });
  assert.equal(r.seen.split('--\n').at(-1), `four.bin ${MiB}\nthree.bin ${2 * MiB}\n`);
});

// A file inside a pasted folder that cannot be copied: a fifo fails as "not a regular file" for any user.
function folderWithFifo(root) {
  const photos = join(root, 'photos');
  mkdirSync(photos);
  writeFileSync(join(photos, 'a.txt'), 'a');
  spawnSync('mkfifo', [join(photos, 'b')]);
  writeFileSync(join(photos, 'c.txt'), 'c');
  return photos;
}

test('skip on a file inside a pasted folder skips only that file and copies the rest', (t) => {
  const { root, dst } = scratch(t);
  const photos = folderWithFifo(root);
  const r = spawnSync(bin, ['copy', dst, photos], { input: 'skip\n', encoding: 'utf8', timeout: 10000 });
  const events = r.stdout.split('\n').filter(Boolean).map((l) => JSON.parse(l));
  assert.equal(r.status, 0, r.stderr);
  assert.equal(events.find((e) => e.event === 'failed').file, join(photos, 'b'));
  assert.deepEqual(readdirSync(join(dst, 'photos')).sort(), ['a.txt', 'c.txt']);
});

test('a folder moved across filesystems with a skipped file keeps its source whole', (t) => {
  const { root } = scratch(t);
  const photos = folderWithFifo(root);
  const mnt = join(root, 'mnt');
  mkdirSync(mnt);
  const r = spawnSync('unshare', ['--user', '--map-root-user', '--mount', 'sh', '-c', `mount -t tmpfs tmpfs '${mnt}' && printf 'skip\\n' | '${bin}' move '${mnt}' '${photos}' && ls '${mnt}/photos'`], { encoding: 'utf8', timeout: 10000 });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /"event":"done"/);
  assert.match(r.stdout, /^a\.txt\nc\.txt$/m);
  assert.deepEqual(readdirSync(photos).sort(), ['a.txt', 'b', 'c.txt']);
});

test('bad usage exits 2', (t) => {
  const { root, dst } = scratch(t);
  const a = join(root, 'a.txt');
  writeFileSync(a, 'a');
  for (const args of [[], ['copy', dst], ['link', dst, a]]) {
    const r = run(...args);
    assert.equal(r.status, 2, args.join(' '));
    assert.deepEqual(r.events, []);
    assert.notEqual(r.stderr, '');
  }
});
