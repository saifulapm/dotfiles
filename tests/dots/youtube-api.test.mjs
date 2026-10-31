// bin/dots-youtube-api, the YouTube App's only network reader: its search rows, its failure kinds, its thumbnail cache and how it leaves no yt-dlp behind. yt-dlp, mise and deno are stubs on a scratch PATH, so no test reaches the network.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, truncateSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const bin = new URL('../../bin/dots-youtube-api', import.meta.url).pathname;

// A scratch home with stubs: mise names the scratch deno unless told to fail, deno prints its version line, and yt-dlp logs each search's argv one per line, then does what the test wrote into its `act` file.
function rig(t, { deno = '2.9.8', mise = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'youtube-api-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'bin'));
  mkdirSync(join(dir, 'deno'));
  const stub = (path, body) => {
    writeFileSync(path, `#!/bin/sh\n${body}\n`);
    chmodSync(path, 0o755);
  };
  stub(join(dir, 'bin', 'mise'), mise ? `echo "${dir}/deno/deno"` : 'echo "mise ERROR deno not found" >&2; exit 1');
  stub(join(dir, 'deno', 'deno'), `echo "deno ${deno} (stable, release, aarch64-unknown-linux-gnu)"`);
  stub(join(dir, 'bin', 'yt-dlp'), `[ "$1" = --version ] && { echo 2026.10.26; exit 0; }\nprintf '%s\\n' "$@" >"${dir}/argv"\n. "${dir}/act"`);
  const env = { PATH: `${dir}/bin:${process.env.PATH}`, HOME: dir, XDG_CACHE_HOME: join(dir, 'cache') };
  const act = (body) => writeFileSync(join(dir, 'act'), body);
  const run = (...args) => spawnSync(bin, args, { env, encoding: 'utf8', timeout: 15000 });
  return { dir, env, act, run };
}

// 20 flat-playlist entries as yt-dlp gives them, with fields the CLI must drop; entry 1 has no channel, only an uploader, and entry 2 no duration.
function canned(length = 20) {
  const entries = Array.from({ length }, (_, i) => ({
    _type: 'url',
    ie_key: 'Youtube',
    id: `vid${String(i).padStart(8, '0')}`,
    url: `https://www.youtube.com/watch?v=vid${String(i).padStart(8, '0')}`,
    title: `Track ${i} [Official Audio]`,
    channel: `Channel ${i}`,
    channel_id: `UC${i}`,
    uploader: `Uploader ${i}`,
    duration: 100 + i,
    view_count: 1000 * i,
    thumbnails: [{ url: `https://i.ytimg.com/vi/vid${String(i).padStart(8, '0')}/hqdefault.jpg`, height: 202, width: 360 }],
  }));
  delete entries[1].channel;
  entries[2].duration = null;
  return JSON.stringify({ _type: 'playlist', id: 'nujabes', title: 'nujabes', entries });
}

test('search prints 20 rows of id, kind, title, channel, duration and thumb, asking yt-dlp for the videos filter, the page at the offset and the deno mise names', (t) => {
  const { dir, act, run } = rig(t);
  writeFileSync(join(dir, 'canned.json'), canned());
  act(`cat "${dir}/canned.json"`);
  const r = run('search', 'lo fi', 'videos', '40');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trimEnd().split('\n').length, 1);
  const { rows } = JSON.parse(r.stdout);
  assert.equal(rows.length, 20);
  for (const row of rows) assert.deepEqual(Object.keys(row), ['id', 'kind', 'title', 'channel', 'duration', 'thumb']);
  assert.deepEqual(rows[0], { id: 'vid00000000', kind: 'video', title: 'Track 0 [Official Audio]', channel: 'Channel 0', duration: 100, thumb: 'vid00000000' });
  assert.equal(rows[1].channel, 'Uploader 1');
  assert.equal(rows[2].duration, null);
  const argv = readFileSync(join(dir, 'argv'), 'utf8').trimEnd().split('\n');
  const after = (flag) => argv[argv.indexOf(flag) + 1];
  assert.ok(argv.includes('--flat-playlist') && argv.includes('-J'), argv.join(' '));
  assert.ok(!argv.includes('--write-pages'), argv.join(' '));
  assert.equal(after('--playlist-start'), '41');
  assert.equal(after('--playlist-end'), '70', 'ten past the page, for the channel cards the filter lets through');
  assert.equal(after('--js-runtimes'), `deno:${dir}/deno/deno`);
  assert.ok(argv.includes('https://www.youtube.com/results?search_query=lo+fi&sp=EgIQAQ%3D%3D'), argv.join(' '));
});

// YouTube's videos filter still lists a channel's card now and then (live, 2 of 20 for nujabes); a card is no video to play, so the page fills from the entries past it, and next says where the following page starts.
test('a channel card or a null entry among the videos is dropped, the page still holds 20, and next follows the last one kept', (t) => {
  const { dir, act, run } = rig(t);
  const data = JSON.parse(canned(30));
  data.entries[0] = { _type: 'url', ie_key: 'YoutubeTab', id: 'UCO5XcuQe_fLJVI3sZ0LmGCA', url: 'https://www.youtube.com/channel/UCO5XcuQe_fLJVI3sZ0LmGCA', title: 'Nujabes', channel: 'Nujabes' };
  data.entries[6] = { _type: 'url', ie_key: 'YoutubeTab', id: 'UCxQQET-tQsC4cwzLow9ZsuQ', url: 'https://www.youtube.com/channel/UCxQQET-tQsC4cwzLow9ZsuQ', title: 'Nujabes - Topic' };
  data.entries[9] = null;
  writeFileSync(join(dir, 'canned.json'), JSON.stringify(data));
  act(`cat "${dir}/canned.json"`);
  const r = run('search', 'nujabes', 'videos', '40');
  assert.equal(r.status, 0, r.stderr);
  const a = JSON.parse(r.stdout);
  assert.equal(a.rows.length, 20);
  assert.ok(a.rows.every((row) => /^vid[0-9]{8}$/.test(row.id)), a.rows.map((row) => row.id).join(' '));
  assert.equal(a.rows[19].id, 'vid00000022');
  assert.equal(a.next, 63);
});

// Search entries as yt-dlp 2026.10.26 gave them live for `nujabes`: the playlists and channels filters both list channel cards, and no flat entry carries a playlist's count.
const nujabesCard = { _type: 'url', ie_key: 'YoutubeTab', id: 'UCO5XcuQe_fLJVI3sZ0LmGCA', url: 'https://www.youtube.com/channel/UCO5XcuQe_fLJVI3sZ0LmGCA', title: 'Nujabes', channel: 'Nujabes', uploader_id: '@Nujabes19740207', thumbnails: [{ url: 'https://yt3.ggpht.com/ytc/AIdro_kQR6ZLejMlmjEV3Jr_avZ3QucWE6b34SciJ1rGU2zXYg=s88-c-k-c0x00ffffff-no-rj-mo', height: 88, width: 88 }], playlist_count: null };
const topicCard = { _type: 'url', ie_key: 'YoutubeTab', id: 'UCxQQET-tQsC4cwzLow9ZsuQ', url: 'https://www.youtube.com/channel/UCxQQET-tQsC4cwzLow9ZsuQ', title: 'Nujabes - Topic', channel: 'Nujabes - Topic', uploader_id: null, thumbnails: [{ url: 'https://yt3.ggpht.com/ytc/AIdro_kQR6ZLejMlmjEV3Jr_avZ3QucWE6b34SciJ1rGU2zXYg=s88-c-k-c0x00ffffff-no-rj-mo', height: 88, width: 88 }], playlist_count: null };
const listEntry = (id, title, channel, video) => ({ _type: 'url', ie_key: 'YoutubeTab', id, url: `https://www.youtube.com/playlist?list=${id}`, title, channel, uploader: channel, duration: null, playlist_count: null, thumbnails: [{ url: `https://i.ytimg.com/vi/${video}/hq720.jpg?sqp=-oaymwExCOgCEMoBSFryq4qpAyMIARUAAIhCGAHwAQH4Af4JgALQBYoCDAgAEAEYfyAqKB8wDw==`, height: 202, width: 360 }] });

// A search result's lockup as YouTube's pages carry it, its count deep in a thumbnail badge.
const lockup = (id, title, count) => ({
  lockupViewModel: {
    contentImage: { collectionThumbnailViewModel: { primaryThumbnail: { thumbnailViewModel: { overlays: [{ thumbnailOverlayBadgeViewModel: { thumbnailBadges: [{ thumbnailBadgeViewModel: { icon: { sources: [{ clientResource: { imageName: 'PLAYLISTS' } }] }, text: count } }] } }] } } } },
    metadata: { lockupMetadataViewModel: { title: { content: title } } },
    contentId: id,
    contentType: 'LOCKUP_CONTENT_TYPE_PLAYLIST',
  },
});

test('a playlists search prints playlist rows, each with the count the pages yt-dlp fetched name, dropping channel cards and a repeated id', (t) => {
  const { dir, act, run } = rig(t);
  const flat = { _type: 'playlist', id: 'nujabes', title: 'nujabes', playlist_count: null, entries: [
    nujabesCard,
    topicCard,
    listEntry('PLfFNYT1NiTNTj04xlfqK8zZUp8sC2ZOAO', 'Modal Soul [Official Audio]', 'Nujabes', 'hQ5x8pHoIPA'),
    listEntry('PLUzwRBBmKGAiXhMgP8TahswgiwwGcKUz1', 'Nujabes Mix', 'Lofi Room', 'LbeiNME75ZE'),
    listEntry('PLUzwRBBmKGAiXhMgP8TahswgiwwGcKUz1', 'Nujabes Mix', 'Lofi Room', 'LbeiNME75ZE'),
    listEntry('PLrVMWXVn39RROm27kBJfg1AUVPgHiXGYG', 'Samurai Champloo', 'Anime OST', '2wK27xW4OFI'),
  ] };
  writeFileSync(join(dir, 'flat.json'), JSON.stringify(flat));
  // The results page is HTML holding ytInitialData; a continuation is JSON; a third page is cut short and names nothing.
  const initial = { contents: { twoColumnSearchResultsRenderer: { primaryContents: { sectionListRenderer: { contents: [{ itemSectionRenderer: { contents: [lockup('PLfFNYT1NiTNTj04xlfqK8zZUp8sC2ZOAO', 'Modal Soul [Official Audio]', '14 videos')] } }] } } } } };
  writeFileSync(join(dir, 'results.dump'), `<!DOCTYPE html><html><head><script nonce="x">var ytInitialData = ${JSON.stringify(initial)};</script><script nonce="x">var other = {};</script></head></html>`);
  const more = { onResponseReceivedCommands: [{ appendContinuationItemsAction: { continuationItems: [{ itemSectionRenderer: { contents: [lockup('PLUzwRBBmKGAiXhMgP8TahswgiwwGcKUz1', 'Nujabes Mix', '1,234 videos')] } }] } }] };
  writeFileSync(join(dir, 'page_1.dump'), JSON.stringify(more));
  writeFileSync(join(dir, 'page_2.dump'), '{"onResponseReceivedCommands": [');
  act(`cp "${dir}/results.dump" "query_nujabes_https_-_www.youtube.com_results.dump"\ncp "${dir}/page_1.dump" "query_nujabes_page_1_https_-_www.youtube.com_youtubei_v1_search.dump"\ncp "${dir}/page_2.dump" "query_nujabes_page_2_https_-_www.youtube.com_youtubei_v1_search.dump"\npwd >"${dir}/cwd"\ncat "${dir}/flat.json"`);
  const r = run('search', 'nujabes', 'playlists', '0');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), {
    rows: [
      { id: 'PLfFNYT1NiTNTj04xlfqK8zZUp8sC2ZOAO', kind: 'playlist', title: 'Modal Soul [Official Audio]', channel: 'Nujabes', duration: null, thumb: 'hQ5x8pHoIPA', count: 14 },
      { id: 'PLUzwRBBmKGAiXhMgP8TahswgiwwGcKUz1', kind: 'playlist', title: 'Nujabes Mix', channel: 'Lofi Room', duration: null, thumb: 'LbeiNME75ZE', count: 1234 },
      { id: 'PLrVMWXVn39RROm27kBJfg1AUVPgHiXGYG', kind: 'playlist', title: 'Samurai Champloo', channel: 'Anime OST', duration: null, thumb: '2wK27xW4OFI', count: null },
    ],
    next: 6,
  });
  const argv = readFileSync(join(dir, 'argv'), 'utf8').trimEnd().split('\n');
  assert.ok(argv.includes('--write-pages'), argv.join(' '));
  assert.ok(argv.includes('https://www.youtube.com/results?search_query=nujabes&sp=EgIQAw%3D%3D'), argv.join(' '));
  // yt-dlp wrote its pages into a directory of the CLI's own, gone once the search answered.
  const cwd = readFileSync(join(dir, 'cwd'), 'utf8').trim();
  assert.notEqual(cwd, process.cwd());
  assert.ok(!existsSync(cwd), cwd);
});

test('a channels search prints channel rows with the handle as channel, dropping a repeated id, and asks for no pages', (t) => {
  const { dir, act, run } = rig(t);
  const flat = { _type: 'playlist', id: 'nujabes', title: 'nujabes', playlist_count: null, entries: [nujabesCard, topicCard, nujabesCard] };
  writeFileSync(join(dir, 'flat.json'), JSON.stringify(flat));
  act(`cat "${dir}/flat.json"`);
  const r = run('search', 'nujabes', 'channels', '20');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), {
    rows: [
      { id: 'UCO5XcuQe_fLJVI3sZ0LmGCA', kind: 'channel', title: 'Nujabes', channel: '@Nujabes19740207', duration: null, thumb: '' },
      { id: 'UCxQQET-tQsC4cwzLow9ZsuQ', kind: 'channel', title: 'Nujabes - Topic', channel: '', duration: null, thumb: '' },
    ],
    next: 22,
  });
  const argv = readFileSync(join(dir, 'argv'), 'utf8').trimEnd().split('\n');
  assert.ok(!argv.includes('--write-pages'), argv.join(' '));
  assert.ok(argv.includes('https://www.youtube.com/results?search_query=nujabes&sp=EgIQAg%3D%3D'), argv.join(' '));
});

const denoLine = { error: 'yt-dlp needs deno 2.3 or newer: run dots update', kind: 'runtime', raw: '' };

test('with mise naming no deno, search fails as runtime before yt-dlp searches', (t) => {
  const { dir, act, run } = rig(t, { mise: false });
  act('echo "{}"');
  const r = run('search', 'nujabes', 'videos', '0');
  assert.equal(r.status, 1);
  assert.deepEqual(JSON.parse(r.stdout), denoLine);
  assert.ok(!existsSync(join(dir, 'argv')));
});

test('with deno 2.2.9, search fails as runtime before yt-dlp searches', (t) => {
  const { dir, act, run } = rig(t, { deno: '2.2.9' });
  act('echo "{}"');
  const r = run('search', 'nujabes', 'videos', '0');
  assert.equal(r.status, 1);
  assert.deepEqual(JSON.parse(r.stdout), denoLine);
  assert.ok(!existsSync(join(dir, 'argv')));
});

test('a bot check from yt-dlp is an extraction failure naming its version, with its ERROR line as raw', (t) => {
  const { act, run } = rig(t);
  act(`echo "WARNING: [youtube] some formats may be missing" >&2\necho "ERROR: [youtube] Sign in to confirm you're not a bot" >&2\nexit 1`);
  const r = run('search', 'nujabes', 'videos', '0');
  assert.equal(r.status, 1);
  assert.deepEqual(JSON.parse(r.stdout), {
    error: 'yt-dlp 2026.10.26 may be behind YouTube: run dots bump, then dots update',
    kind: 'extraction',
    raw: "ERROR: [youtube] Sign in to confirm you're not a bot",
  });
});

test('a failed name lookup from yt-dlp is a network failure', (t) => {
  const { act, run } = rig(t);
  act(`echo "ERROR: Unable to download API page: <urlopen error [Errno -3] Temporary failure in name resolution>" >&2\nexit 1`);
  const r = run('search', 'nujabes', 'videos', '0');
  assert.equal(r.status, 1);
  assert.deepEqual(JSON.parse(r.stdout), {
    error: 'No network. Check Wi-Fi, then ↵ to try again.',
    kind: 'network',
    raw: 'ERROR: Unable to download API page: <urlopen error [Errno -3] Temporary failure in name resolution>',
  });
});

test('thumbs fetches each good id into the cache and lists it, leaving out a failed fetch and ignoring a bad id', (t) => {
  const { dir, env } = rig(t);
  mkdirSync(join(dir, 'src'));
  writeFileSync(join(dir, 'src', 'aaaaaaaaaaa.jpg'), 'jpeg a');
  writeFileSync(join(dir, 'src', 'bbbbbbbbb-_.jpg'), 'jpeg b');
  const r = spawnSync(bin, ['thumbs', 'aaaaaaaaaaa', 'bbbbbbbbb-_', 'ccccccccccc', 'bad/id'], { env: { ...env, DOTS_YOUTUBE_THUMB_URL: `file://${dir}/src/{id}.jpg` }, encoding: 'utf8', timeout: 15000 });
  assert.equal(r.status, 0, r.stderr);
  const thumbs = join(dir, 'cache', 'dots', 'youtube', 'thumbs');
  assert.deepEqual(JSON.parse(r.stdout), { dir: thumbs, files: { aaaaaaaaaaa: join(thumbs, 'aaaaaaaaaaa.jpg'), 'bbbbbbbbb-_': join(thumbs, 'bbbbbbbbb-_.jpg') } });
  assert.equal(readFileSync(join(thumbs, 'aaaaaaaaaaa.jpg'), 'utf8'), 'jpeg a');
  assert.deepEqual(readdirSync(thumbs).sort(), ['aaaaaaaaaaa.jpg', 'bbbbbbbbb-_.jpg']);
});

// mqdefault is 320x180, the size the App draws at no more than 2x (5TBCGNV6); the CLI runs under python with urlopen recording what it is asked, so no test reaches i.ytimg.com.
test('thumbs asks i.ytimg.com for the 320x180 mqdefault of each id when nothing replaces the URL', (t) => {
  const { env } = rig(t);
  const probe = `import runpy, sys, urllib.request
asked = []
def urlopen(url, timeout):
    asked.append(url)
    raise OSError("offline")
urllib.request.urlopen = urlopen
sys.argv = ["dots-youtube-api", "thumbs", "dQw4w9WgXcQ"]
try:
    runpy.run_path(${JSON.stringify(bin)}, run_name="__main__")
except SystemExit:
    pass
print(asked, file=sys.stderr)`;
  const r = spawnSync('python3', ['-c', probe], { env, encoding: 'utf8', timeout: 15000 });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stderr.trim(), "['https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg']");
});

test('thumbs prunes the cache to 200 MiB, oldest first, keeping the newest', (t) => {
  const { dir, env } = rig(t);
  const thumbs = join(dir, 'cache', 'dots', 'youtube', 'thumbs');
  mkdirSync(thumbs, { recursive: true });
  // Five sparse 50 MiB files, 250 MiB in all, each a minute older than the next; the newest is asked for, so its mtime moves to now.
  const names = ['old00000001', 'old00000002', 'old00000003', 'old00000004', 'new00000005'];
  const now = Date.now() / 1000;
  names.forEach((n, i) => {
    const p = join(thumbs, `${n}.jpg`);
    writeFileSync(p, '');
    truncateSync(p, 50 * 1024 * 1024);
    utimesSync(p, now - 600 + i * 60, now - 600 + i * 60);
  });
  const r = spawnSync(bin, ['thumbs', 'new00000005'], { env: { ...env, DOTS_YOUTUBE_THUMB_URL: `file://${dir}/none/{id}.jpg` }, encoding: 'utf8', timeout: 15000 });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(readdirSync(thumbs).sort(), ['new00000005.jpg', 'old00000002.jpg', 'old00000003.jpg', 'old00000004.jpg']);
  const total = readdirSync(thumbs).reduce((s, f) => s + statSync(join(thumbs, f)).size, 0);
  assert.ok(total <= 209715200, String(total));
  assert.deepEqual(JSON.parse(r.stdout).files, { new00000005: join(thumbs, 'new00000005.jpg') });
});

const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

// Starts a search whose yt-dlp sleeps 30 s, sends the CLI the signal once yt-dlp is up, and resolves with whether the stub still runs 2 s later.
async function orphanAfter(t, signal) {
  const { dir, env, act } = rig(t);
  act(`echo $$ >"${dir}/pid"\nexec sleep 30`);
  const child = spawn(bin, ['search', 'nujabes', 'videos', '0'], { env, stdio: 'ignore' });
  const pidFile = join(dir, 'pid');
  for (let i = 0; i < 100 && !(existsSync(pidFile) && readFileSync(pidFile, 'utf8').trim()); i++) await new Promise((r) => setTimeout(r, 50));
  const pid = Number(readFileSync(pidFile, 'utf8'));
  t.after(() => alive(pid) && process.kill(pid, 'SIGKILL'));
  const exited = new Promise((r) => child.on('exit', r));
  child.kill(signal);
  await exited;
  for (let i = 0; i < 20 && alive(pid); i++) await new Promise((r) => setTimeout(r, 100));
  return alive(pid);
}

test('SIGTERM to the CLI leaves no yt-dlp running', async (t) => {
  assert.equal(await orphanAfter(t, 'SIGTERM'), false);
});

test('SIGKILL to the CLI leaves no yt-dlp running', async (t) => {
  assert.equal(await orphanAfter(t, 'SIGKILL'), false);
});
