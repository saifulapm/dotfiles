// bin/dots-youtube-get, the YouTube App's downloader: its queue, its one worker unit, its index and what it tells the island. yt-dlp, mise, deno, systemd-run, systemctl and dots-call are stubs on a scratch PATH; the systemd-run stub runs the worker in the background, so the queue really drains.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const source = new URL('../../bin/dots-youtube-get', import.meta.url).pathname;
const TEMPLATE = 'download:{"pct":"%(progress._percent_str)s","s":"%(progress.status)s"}';

// Logs its argv one per line to argv-<id>, marks itself busy so two at once show in `overlap`, prints yt-dlp's progress lines (a second run for a video), then writes the file under -P home: and prints the after_move line, or fails as the `fail` file says for its id.
const YTDLP = `#!/bin/bash
id=\${@: -1}; id=\${id##*v=}
printf '%s\\n' "$@" >"$STUB_REC/argv-$id"
mkdir "$STUB_REC/busy" 2>/dev/null || echo "$id" >>"$STUB_REC/overlap"
trap 'rmdir "$STUB_REC/busy" 2>/dev/null' EXIT
ext=webm; runs=2
while [ $# -gt 1 ]; do
  case $1 in
  -x) ext=opus; runs=1 ;;
  -P) case $2 in home:*) home=\${2#home:} ;; temp:*) temp=\${2#temp:} ;; esac; shift ;;
  --print) print=\${2#after_move:}; shift ;;
  esac
  shift
done
tick() { printf '{"pct":"%5.1f%%","s":"%s"}\\n' "$1" "$2"; sleep 0.02; }
reason=$(grep "^$id " "$STUB_ROOT/fail" 2>/dev/null | cut -d' ' -f2-)
if [ -n "$reason" ]; then
  tick 12 downloading
  mkdir -p "$temp" && echo part >"$temp/x.part"
  echo "WARNING: something minor" >&2
  echo "$reason" >&2
  exit 1
fi
for _ in $(seq $runs); do tick 0 downloading; tick 50 downloading; tick 100 finished; done
mkdir -p "$home"
file="$home/Stub $id [$id].$ext"
grep -qx "$id" "$STUB_ROOT/escape" 2>/dev/null && file="$STUB_ROOT/Stub $id.$ext"
echo media >"$file"
echo "$id" >>"$STUB_REC/downloads"
printf '%s\\n' "\${print//%(filepath)s/$file}"
`;

// Refuses the name while a worker it started still runs, as systemd does, and logs each start and end to `units`.
const SYSTEMD_RUN = `#!/bin/bash
printf '%s\\n' "$*" >>"$STUB_REC/systemd-run"
while [ $# -gt 0 ]; do
  case $1 in --setenv=*=*) export "\${1#--setenv=}" ;; --) shift; break ;; esac
  shift
done
slot=$STUB_REC/unit
if ! mkdir "$slot" 2>/dev/null; then
  kill -0 "$(cat "$slot/pid" 2>/dev/null)" 2>/dev/null && { echo "Unit already exists" >&2; exit 1; }
  rm -rf "$slot"; mkdir "$slot"
fi
echo start >>"$STUB_REC/units"
setsid bash -c '"$@"; echo end >>"$STUB_REC/units"; rm -rf "$STUB_REC/unit"' _ "$@" </dev/null >>"$STUB_REC/worker.log" 2>&1 &
echo $! >"$slot/pid"
`;

function rig(t) {
  const root = mkdtempSync(join(tmpdir(), 'youtube-get-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const stubs = join(root, 'stubs');
  const rec = join(root, 'rec');
  for (const d of [stubs, rec, join(root, 'deno'), join(root, 'run')]) mkdirSync(d, { recursive: true });
  const stub = (path, body) => {
    writeFileSync(path, body);
    chmodSync(path, 0o755);
  };
  stub(join(stubs, 'yt-dlp'), YTDLP);
  stub(join(stubs, 'systemd-run'), SYSTEMD_RUN);
  stub(join(stubs, 'systemctl'), '#!/bin/bash\nkill -0 "$(cat "$STUB_REC/unit/pid" 2>/dev/null)" 2>/dev/null\n');
  stub(join(stubs, 'mise'), `#!/bin/bash\necho "${root}/deno/deno"\n`);
  stub(join(root, 'deno', 'deno'), '#!/bin/bash\necho "deno 2.9.8"\n');
  // The script calls the dots-call beside it, so a copy runs from the stubs with a recording dots-call next to it.
  copyFileSync(source, join(stubs, 'dots-youtube-get'));
  chmodSync(join(stubs, 'dots-youtube-get'), 0o755);
  stub(join(stubs, 'dots-call'), '#!/bin/bash\nprintf \'%s\\n\' "$*" >>"$STUB_REC/dots-call"\n');
  const env = {
    PATH: `${stubs}:${process.env.PATH}`,
    HOME: root,
    XDG_RUNTIME_DIR: join(root, 'run'),
    XDG_STATE_HOME: join(root, 'state'),
    XDG_CACHE_HOME: join(root, 'cache'),
    XDG_MUSIC_DIR: join(root, 'Music'),
    XDG_VIDEOS_DIR: join(root, 'Videos'),
    STUB_REC: rec,
    STUB_ROOT: root,
  };
  const bin = join(stubs, 'dots-youtube-get');
  const rows = (list) => list.map(([id, title]) => JSON.stringify({ id, title })).join('\n') + '\n';
  const run = (args, input = '') => spawnSync(bin, args, { env, input, encoding: 'utf8', timeout: 15000 });
  const read = (n) => (existsSync(join(rec, n)) ? readFileSync(join(rec, n), 'utf8') : null);
  const lines = (n) => (read(n) ?? '').split('\n').filter(Boolean);
  const indexPath = join(root, 'state', 'dots', 'youtube', 'downloads.json');
  const index = () => JSON.parse(readFileSync(indexPath, 'utf8'));
  const queue = () => JSON.parse(readFileSync(join(root, 'run', 'dots', 'youtube-get.json'), 'utf8'));
  // Waits for the worker to tell the island it is done and leave the queue empty and not running.
  const settle = async () => {
    for (let i = 0; i < 300; i++) {
      if (lines('dots-call').at(-1) === 'downloading done' && !existsSync(join(rec, 'unit')) && !queue().running) return;
      await new Promise((r) => setTimeout(r, 50));
    }
    assert.fail(`the queue never drained: ${read('dots-call')} ${read('worker.log')}`);
  };
  return { root, stubs, rec, env, bin, rows, run, read, lines, index, indexPath, settle };
}

const argvOf = (ctx, id) => ctx.read(`argv-${id}`).trimEnd().split('\n');
const progress = (ctx) => ctx.lines('dots-call').filter((l) => l.startsWith('downloading progress ')).map((l) => Number(l.split(' ')[2]));

test('an audio enqueue downloads bestaudio with tags and cover into the music folder, indexes it and tells the island', async (t) => {
  const ctx = rig(t);
  const r = ctx.run(['audio'], ctx.rows([['aaaaaaaaaa1', 'Feather']]));
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, '{"queued":1}\n');
  await ctx.settle();
  const music = join(ctx.root, 'Music', 'YouTube');
  assert.deepEqual(argvOf(ctx, 'aaaaaaaaaa1'), [
    '-f', 'bestaudio', '-x', '--embed-thumbnail', '--embed-metadata', '--convert-thumbnails', 'jpg',
    '--replace-in-metadata', 'title', '^[\\s-]+|[\\u200e\\u200f\\u061c\\u202a-\\u202e\\u2066-\\u2069]', '',
    '--no-playlist', '--newline', '--progress', '--progress-template', TEMPLATE,
    '-o', '%(title).70B [%(id)s].%(ext)s', '-P', `home:${music}`, '-P', `temp:${join(ctx.root, 'cache', 'dots', 'youtube-get', 'aaaaaaaaaa1')}`,
    '--print', 'after_move:file %(filepath)s', '--js-runtimes', `deno:${join(ctx.root, 'deno', 'deno')}`,
    'https://www.youtube.com/watch?v=aaaaaaaaaa1',
  ]);
  const file = join(music, 'Stub aaaaaaaaaa1 [aaaaaaaaaa1].opus');
  assert.deepEqual(ctx.index(), { files: { aaaaaaaaaa1: { audio: file } }, failed: {} });
  const calls = ctx.lines('dots-call');
  assert.equal(calls[0], 'downloading start 1 1  Feather audio');
  assert.deepEqual(progress(ctx), [0, 50, 100]);
  assert.equal(calls.at(-1), 'downloading done');
  const start = ctx.lines('systemd-run')[0];
  assert.ok(start.startsWith('--user --collect --quiet --unit youtube-get '), start);
  assert.ok(start.includes(`--setenv=DOTS_YOUTUBE_YTDLP=${join(ctx.stubs, 'yt-dlp')}`), start);
  assert.ok(start.endsWith(`-- ${ctx.bin} run`), start);
  assert.ok(!existsSync(join(ctx.root, 'cache', 'dots', 'youtube-get', 'aaaaaaaaaa1')), 'the temp folder is gone');
});

test('a video goes to the videos folder at most 1080p, and its percent never falls across its two streams', async (t) => {
  const ctx = rig(t);
  assert.equal(ctx.run(['video'], ctx.rows([['vvvvvvvvvv1', 'Focus']])).stdout, '{"queued":1}\n');
  await ctx.settle();
  const argv = argvOf(ctx, 'vvvvvvvvvv1');
  assert.deepEqual(argv.slice(0, 3), ['-f', 'bv*[height<=1080]+ba/b[height<=1080]', '--embed-metadata']);
  assert.ok(!argv.includes('-x'), argv.join(' '));
  const file = join(ctx.root, 'Videos', 'YouTube', 'Stub vvvvvvvvvv1 [vvvvvvvvvv1].webm');
  assert.equal(argv[argv.indexOf('-P') + 1], `home:${join(ctx.root, 'Videos', 'YouTube')}`);
  assert.deepEqual(ctx.index().files, { vvvvvvvvvv1: { video: file } });
  assert.equal(ctx.lines('dots-call')[0], 'downloading start 1 1  Focus video');
  assert.deepEqual(progress(ctx), [0, 50, 100]);
});

test('an id already downloaded queues nothing and starts no unit; once its file is gone, where drops it', async (t) => {
  const ctx = rig(t);
  const file = join(ctx.root, 'Music', 'YouTube', 'Feather [aaaaaaaaaa1].opus');
  mkdirSync(join(ctx.root, 'Music', 'YouTube'), { recursive: true });
  writeFileSync(file, 'media');
  mkdirSync(join(ctx.root, 'state', 'dots', 'youtube'), { recursive: true });
  writeFileSync(ctx.indexPath, JSON.stringify({ files: { aaaaaaaaaa1: { audio: file } }, failed: {} }));
  const r = ctx.run(['audio'], ctx.rows([['aaaaaaaaaa1', 'Feather']]));
  assert.equal(r.stdout, '{"queued":0}\n', r.stderr);
  assert.equal(ctx.read('systemd-run'), null);
  assert.equal(ctx.run(['where', 'aaaaaaaaaa1']).stdout, `{"files":{"aaaaaaaaaa1":{"audio":"${file}"}}}\n`);
  rmSync(file);
  assert.equal(ctx.run(['where', 'aaaaaaaaaa1']).stdout, '{"files":{}}\n');
  assert.deepEqual(ctx.index(), { files: {}, failed: {} });
});

test('ten enqueues at once download ten files, one yt-dlp and one unit at a time, none twice', async (t) => {
  const ctx = rig(t);
  const ids = Array.from({ length: 10 }, (_, i) => `tenfast00${String(i).padStart(2, '0')}`);
  await Promise.all(ids.map((id) => new Promise((resolve) => {
    const p = spawn(ctx.bin, ['audio'], { env: ctx.env, stdio: ['pipe', 'pipe', 'inherit'] });
    let out = '';
    p.stdout.on('data', (d) => (out += d));
    p.on('close', (code) => {
      assert.equal(code, 0);
      assert.equal(out, '{"queued":1}\n');
      resolve();
    });
    p.stdin.end(ctx.rows([[id, `Song ${id}`]]));
  })));
  for (let i = 0; i < 300 && Object.keys(JSON.parse(existsSync(ctx.indexPath) ? readFileSync(ctx.indexPath, 'utf8') : '{"files":{}}').files).length < 10; i++) await new Promise((r) => setTimeout(r, 50));
  await ctx.settle();
  assert.deepEqual(Object.keys(ctx.index().files).sort(), ids);
  for (const id of ids) assert.ok(existsSync(ctx.index().files[id].audio), id);
  assert.equal(ctx.read('overlap'), null, 'yt-dlp ran twice at once');
  assert.deepEqual(ctx.lines('downloads').sort(), ids);
  const units = ctx.lines('units');
  units.forEach((u, i) => assert.equal(u, i % 2 ? 'end' : 'start', units.join(' ')));
});

test('a Playlist enqueue counts only the rows not yet downloaded', async (t) => {
  const ctx = rig(t);
  const file = join(ctx.root, 'Videos', 'YouTube', 'One [pppppppppp1].webm');
  mkdirSync(join(ctx.root, 'Videos', 'YouTube'), { recursive: true });
  writeFileSync(file, 'media');
  mkdirSync(join(ctx.root, 'state', 'dots', 'youtube'), { recursive: true });
  writeFileSync(ctx.indexPath, JSON.stringify({ files: { pppppppppp1: { video: file } }, failed: {} }));
  const r = ctx.run(['video', '--playlist', 'Focus'], ctx.rows([['pppppppppp1', 'One'], ['pppppppppp2', 'Two'], ['pppppppppp3', 'Three']]));
  assert.equal(r.stdout, '{"queued":2}\n', r.stderr);
  await ctx.settle();
  const starts = ctx.lines('dots-call').filter((l) => l.startsWith('downloading start '));
  assert.deepEqual(starts, ['downloading start 1 2 Focus Two video', 'downloading start 2 2 Focus Three video']);
});

test('a failed download tells the island why, is indexed as failed, leaves no partial file, and the queue goes on', async (t) => {
  const ctx = rig(t);
  writeFileSync(join(ctx.root, 'fail'), [
    'ffffffffff1 ERROR: [youtube] ffffffffff1: Unable to download video data: HTTP Error 403: Forbidden',
    'ffffffffff2 ERROR: unable to write data: [Errno 28] No space left on device',
  ].join('\n') + '\n');
  const r = ctx.run(['audio', '--playlist', 'Mix'], ctx.rows([['ffffffffff1', 'Bad'], ['ffffffffff2', 'Full'], ['gggggggggg1', 'Good']]));
  assert.equal(r.stdout, '{"queued":3}\n', r.stderr);
  await ctx.settle();
  const calls = ctx.lines('dots-call');
  assert.ok(calls.includes('downloading failed Bad HTTP 403'), calls.join('\n'));
  assert.ok(calls.includes('downloading failed Full disk full'), calls.join('\n'));
  assert.ok(calls.includes('downloading start 3 3 Mix Good audio'), calls.join('\n'));
  const index = ctx.index();
  assert.deepEqual(index.failed, {
    ffffffffff1: { kind: 'audio', title: 'Bad', reason: 'HTTP 403' },
    ffffffffff2: { kind: 'audio', title: 'Full', reason: 'disk full' },
  });
  assert.deepEqual(Object.keys(index.files), ['gggggggggg1']);
  assert.deepEqual(readdirSync(join(ctx.root, 'Music', 'YouTube')), ['Stub gggggggggg1 [gggggggggg1].opus']);
  assert.deepEqual(readdirSync(join(ctx.root, 'cache', 'dots', 'youtube-get')), []);
  // A new enqueue of a failed id forgets its failure.
  writeFileSync(join(ctx.root, 'fail'), '');
  assert.equal(ctx.run(['audio'], ctx.rows([['ffffffffff1', 'Bad']])).stdout, '{"queued":1}\n');
  await ctx.settle();
  assert.deepEqual(Object.keys(ctx.index().failed), ['ffffffffff2']);
});

test('odd titles reach yt-dlp only through the -o template, and a file printed outside the folder is not indexed', async (t) => {
  const ctx = rig(t);
  writeFileSync(join(ctx.root, 'escape'), 'eeeeeeeeee3\n');
  const long = 'x'.repeat(300);
  const r = ctx.run(['audio'], ctx.rows([['eeeeeeeeee1', '../../x'], ['eeeeeeeeee2', '-rf'], ['eeeeeeeeee3', long]]) + 'not json\n{"id":"short","title":"t"}\n');
  assert.equal(r.stdout, '{"queued":3}\n', r.stderr);
  await ctx.settle();
  const music = join(ctx.root, 'Music', 'YouTube');
  for (const id of ['eeeeeeeeee1', 'eeeeeeeeee2', 'eeeeeeeeee3']) {
    const argv = argvOf(ctx, id);
    assert.equal(argv[argv.indexOf('-o') + 1], '%(title).70B [%(id)s].%(ext)s');
    assert.deepEqual(argv.filter((a) => a.startsWith('home:') || a.startsWith('temp:')), [`home:${music}`, `temp:${join(ctx.root, 'cache', 'dots', 'youtube-get', id)}`]);
    assert.ok(!argv.some((a) => a.includes('-rf') || a.includes('../../x') || a.includes(long)), argv.join(' '));
  }
  const index = ctx.index();
  assert.deepEqual(Object.keys(index.files).sort(), ['eeeeeeeeee1', 'eeeeeeeeee2']);
  assert.equal(index.files.eeeeeeeeee1.audio, join(music, 'Stub eeeeeeeeee1 [eeeeeeeeee1].opus'));
  assert.ok(ctx.lines('dots-call').includes(`downloading failed ${long} yt-dlp saved no file in the folder`), ctx.read('dots-call'));
  assert.ok(ctx.lines('dots-call').includes('downloading start 1 1  -rf audio'));
});
