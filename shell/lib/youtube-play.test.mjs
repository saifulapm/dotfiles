import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const bin = new URL('../../bin/dots-youtube-play', import.meta.url).pathname;

// A fake systemd-run that logs its argv per call and refuses a unit name in $TAKEN, as the real one refuses a unit that exists; systemctl reads every unit as inactive; mise names a deno.
function rig(t, extra = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'youtube-play-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const stub = (name, body) => {
    writeFileSync(join(dir, name), `#!/bin/sh\n${body}\n`);
    chmodSync(join(dir, name), 0o755);
  };
  // The Queue's mpv makes its socket as it starts, unless $NO_SOCKET says it died first.
  stub('systemd-run', `for a; do case $a in youtube-video-* | youtube-audio) unit=$a ;; --input-ipc-server=*) sock=\${a#*=} ;; esac; done\ncase " $TAKEN " in *" $unit "*) echo "Unit $unit.service was already loaded" >&2; exit 1 ;; esac\nprintf '%s\\n' "$@" > "${dir}/argv-$unit"\n[ -n "$sock" ] && [ -z "$NO_SOCKET" ] && python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$sock"\nexit 0`);
  // Every unit reads inactive unless named in $ACTIVE; each call is logged.
  stub('systemctl', `echo "$*" >> "${dir}/systemctl.log"\nfor a; do case " $ACTIVE " in *" \${a%.service} "*) exit 0 ;; esac; done\nexit 3`);
  stub('mise', `[ "$1 $2" = "which deno" ] && echo /opt/deno/bin/deno`);
  stub('yt-dlp', 'echo 2026.10.26');
  const env = Object.assign({ PATH: `${dir}:/usr/bin:/bin`, HOME: dir, XDG_RUNTIME_DIR: dir }, extra);
  const run = (...args) => spawnSync('bash', [bin, ...args], { env, encoding: 'utf8', timeout: 5000 });
  const argv = (unit) => readFileSync(join(dir, `argv-${unit}`), 'utf8').trimEnd().split('\n');
  const ran = (unit) => existsSync(join(dir, `argv-${unit}`));
  const systemctl = () => (existsSync(join(dir, 'systemctl.log')) ? readFileSync(join(dir, 'systemctl.log'), 'utf8') : '');
  return { dir, run, argv, ran, systemctl };
}

test('a video plays in mpv in the unit youtube-video-1, at most 1080p, reconnecting on 403, with the window up at once', (t) => {
  const { run, argv } = rig(t);
  const r = run('video', 'fakeVid0001');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { unit: 'youtube-video-1' });
  const a = argv('youtube-video-1');
  const cmd = a.slice(a.indexOf('--') + 1);
  assert.equal(cmd[0], 'mpv');
  assert.ok(cmd.includes('--force-window=immediate'));
  assert.ok(cmd.includes('--ytdl-format=bv*[height<=1080]+ba/b[height<=1080]'));
  assert.ok(cmd.includes('--stream-lavf-o=reconnect=1,reconnect_on_http_error=403,reconnect_delay_max=3'));
  assert.equal(cmd[cmd.length - 1], 'https://www.youtube.com/watch?v=fakeVid0001');
});

// A unit's PATH is the user manager's, so yt-dlp is told where deno and itself are (ruling B47Y3V5J).
test('mpv\'s yt-dlp is named by path and given the deno mise names', (t) => {
  const { dir, run, argv } = rig(t);
  run('video', 'fakeVid0001');
  const cmd = argv('youtube-video-1');
  assert.ok(cmd.includes(`--script-opts=ytdl_hook-ytdl_path=${dir}/yt-dlp`), cmd.join(' '));
  assert.ok(cmd.includes('--ytdl-raw-options=js-runtimes=deno:/opt/deno/bin/deno'), cmd.join(' '));
});

test('a second video while the first plays gets the next free unit, each its own', (t) => {
  const { run } = rig(t, { TAKEN: 'youtube-video-1 youtube-video-2' });
  assert.deepEqual(JSON.parse(run('video', 'fakeVid0001').stdout), { unit: 'youtube-video-3' });
});

// mpv-mpris shows a player on the caller's session bus, which a nested check's own bus is, and the user manager's is not.
test('DOTS_YOUTUBE_MPV names the player, and the caller\'s display, bus, dirs and dev dir reach the unit by name', (t) => {
  const { run, argv } = rig(t, { DOTS_YOUTUBE_MPV: '/repo/dev/youtube/mpv', WAYLAND_DISPLAY: 'wayland-7', DBUS_SESSION_BUS_ADDRESS: 'unix:path=/b', XDG_CACHE_HOME: '/c', DOTS_DEV_DIR: '/d', OTHER: 'x' });
  run('video', 'fakeVid0001');
  const a = argv('youtube-video-1');
  assert.deepEqual(a.filter((x) => x.startsWith('--setenv')).sort(), ['--setenv=DBUS_SESSION_BUS_ADDRESS', '--setenv=DOTS_DEV_DIR', '--setenv=WAYLAND_DISPLAY', '--setenv=XDG_CACHE_HOME', '--setenv=XDG_RUNTIME_DIR']);
  assert.equal(a[a.indexOf('--') + 1], '/repo/dev/youtube/mpv');
});

test('audio starts the Queue: mpv idle in the unit youtube-audio, audio only, on its socket under the runtime dir', (t) => {
  const { dir, run, argv } = rig(t);
  const r = run('audio');
  assert.equal(r.status, 0, r.stderr);
  const sock = `${dir}/dots/youtube-audio.sock`;
  assert.deepEqual(JSON.parse(r.stdout), { unit: 'youtube-audio', socket: sock });
  const a = argv('youtube-audio');
  const cmd = a.slice(a.indexOf('--') + 1);
  assert.equal(cmd[0], 'mpv');
  for (const opt of ['--no-video', '--idle=yes', `--input-ipc-server=${sock}`, '--ytdl-format=bestaudio/best', '--stream-lavf-o=reconnect=1,reconnect_on_http_error=403,reconnect_delay_max=3', `--script-opts=ytdl_hook-ytdl_path=${dir}/yt-dlp`])
    assert.ok(cmd.includes(opt), `${opt} in ${cmd.join(' ')}`);
  assert.ok(!cmd.some((x) => x.startsWith('https://')), 'the App loads every item over the socket');
});

// mpv.conf saves each position on quit for videos; a song m plays starts at its top, as the line's 0:00 says.
test('the Queue neither resumes an item where an earlier mpv left it nor saves where it stops', (t) => {
  const { run, argv } = rig(t);
  run('audio');
  const cmd = argv('youtube-audio');
  assert.ok(cmd.includes('--resume-playback=no'), cmd.join(' '));
  assert.ok(cmd.includes('--save-position-on-quit=no'), cmd.join(' '));
});

test('audio with the Queue running and its socket there starts nothing and names it', (t) => {
  const { dir, run, ran } = rig(t, { ACTIVE: 'youtube-audio' });
  mkdirSync(`${dir}/dots`);
  spawnSync('python3', ['-c', 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])', `${dir}/dots/youtube-audio.sock`]);
  const r = run('audio');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { unit: 'youtube-audio', socket: `${dir}/dots/youtube-audio.sock` });
  assert.equal(ran('youtube-audio'), false);
});

// mpv gone with its unit still up, or its socket removed, leaves nothing to talk to, so the Queue starts again.
test('audio with the unit running but no socket stops it and starts a fresh Queue', (t) => {
  const { run, ran, systemctl } = rig(t, { ACTIVE: 'youtube-audio' });
  const r = run('audio');
  assert.equal(r.status, 0, r.stderr);
  assert.match(systemctl(), /stop youtube-audio/);
  assert.equal(ran('youtube-audio'), true);
});

test('a Queue whose socket never comes says so', (t) => {
  const { run } = rig(t, { NO_SOCKET: '1' });
  const r = run('audio');
  assert.equal(r.status, 1);
  assert.match(JSON.parse(r.stdout).error, /youtube-audio/);
});

test('anything but a video id is no video', (t) => {
  const { run } = rig(t);
  assert.equal(run('video', '--input-ipc-server=/tmp/x').status, 2);
  assert.equal(run('video').status, 2);
  assert.equal(run('audio', 'fakeVid0001').status, 2, 'the Queue takes its items over the socket');
});
