// dots-capture as niri's binds and the launcher run it: the screen, the region picker, the clipboard, niri and the shell are stubs, and each test reads what reached wl-copy and the island.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const bin = new URL('../../bin/dots-capture', import.meta.url).pathname;

// stubs: what each stub does in this test; a tool left out runs for real, as tesseract does over a rendered image.
function scratch(t, stubs) {
  const root = mkdtempSync(join(tmpdir(), 'dots-capture-'));
  const dir = join(root, 'stubs');
  const rec = join(root, 'rec');
  const own = join(root, 'bin');
  for (const d of [dir, rec, own, join(root, 'home'), join(root, 'state'), join(root, 'run')]) mkdirSync(d);
  const put = (path, body) => {
    writeFileSync(path, `#!/bin/bash\n${body}\n`);
    chmodSync(path, 0o755);
  };
  const log = (name) => `printf '%s\\n' "${name} $*" >>"$STUB_REC/argv.log"`;
  for (const [name, body] of Object.entries(stubs)) put(join(dir, name), `${log(name)}\n${body}`);
  put(join(dir, 'wl-copy'), `${log('wl-copy')}\necho "$*" >"$STUB_REC/wl-copy.args"\ncat >"$STUB_REC/wl-copy.stdin"`);
  put(join(dir, 'satty'), `${log('satty')}\ncat >"$STUB_REC/satty.stdin"`);
  // niri's spawn need not have bin/ on PATH, so dots-call is the one beside the script, with none on PATH.
  copyFileSync(bin, join(own, 'dots-capture'));
  chmodSync(join(own, 'dots-capture'), 0o755);
  put(join(own, 'dots-call'), `printf '%s\\n' "$@" >"$STUB_REC/dots-call.args"`);
  const env = {
    ...process.env,
    PATH: dir + delimiter + process.env.PATH,
    STUB_REC: rec,
    HOME: join(root, 'home'),
    XDG_STATE_HOME: join(root, 'state'),
    XDG_RUNTIME_DIR: join(root, 'run'),
    LANG: 'C',
  };
  delete env.LC_ALL;
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const run = (...args) => spawnSync(join(own, 'dots-capture'), args, { env, encoding: 'utf8', timeout: 20000 });
  const read = (name) => (existsSync(join(rec, name)) ? readFileSync(join(rec, name), 'utf8') : null);
  return { root, run, read, pill: () => read('dots-call.args')?.split('\n').slice(0, -1) ?? null };
}

const REGION = `echo '10,20 300x40'`;
const SCREEN = `echo screen-png`;

test('ocr copies the trimmed text of the picked region and counts it in the pill', (t) => {
  const s = scratch(t, { slurp: REGION, grim: SCREEN, tesseract: `printf '  Ship v2 today\\n\\n\\f'` });
  const r = s.run('ocr');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(s.read('wl-copy.stdin'), 'Ship v2 today');
  assert.equal(s.read('wl-copy.args'), '\n');
  assert.deepEqual(s.pill(), ['island', 'capture', 'ocr', 'Text copied', '13 characters']);
  assert.match(s.read('argv.log'), /^grim -g 10,20 300x40 -$/m);
  assert.match(s.read('argv.log'), /^tesseract - - -l eng\+ben$/m);
});

test('ocr counts Bangla in characters, not bytes', (t) => {
  const s = scratch(t, { slurp: REGION, grim: SCREEN, tesseract: `printf 'আমার সোনার\\n'` });
  s.run('ocr');
  assert.equal(s.read('wl-copy.stdin'), 'আমার সোনার');
  assert.deepEqual(s.pill(), ['island', 'capture', 'ocr', 'Text copied', '10 characters']);
});

test('ocr over an empty region says No text found and leaves the clipboard alone', (t) => {
  const s = scratch(t, { slurp: REGION, grim: SCREEN, tesseract: `printf ' \\n\\f'` });
  const r = s.run('ocr');
  assert.equal(r.status, 0, r.stderr);
  assert.equal(s.read('wl-copy.args'), null);
  assert.deepEqual(s.pill(), ['island', 'capture', 'ocr', '', 'No text found']);
});

test('--region skips slurp', (t) => {
  const s = scratch(t, { slurp: 'exit 1', grim: SCREEN, tesseract: `echo hi` });
  s.run('ocr', '--region', '5,6 70x80');
  assert.doesNotMatch(s.read('argv.log'), /^slurp/m);
  assert.match(s.read('argv.log'), /^grim -g 5,6 70x80 -$/m);
  assert.equal(s.read('wl-copy.stdin'), 'hi');
});

test('Escape at slurp does nothing and shows nothing', (t) => {
  for (const mode of ['ocr', 'qr', 'annotate']) {
    const s = scratch(t, { slurp: 'echo "selection cancelled" >&2; exit 1', grim: SCREEN, tesseract: 'echo x', zbarimg: 'echo x' });
    const r = s.run(mode);
    assert.equal(r.status, 0, `${mode}: ${r.stderr}`);
    assert.doesNotMatch(s.read('argv.log'), /^(grim|wl-copy|satty)/m, mode);
    assert.equal(s.pill(), null, mode);
  }
});

test('qr copies the code as sensitive, so the clip store drops it', (t) => {
  const s = scratch(t, { slurp: REGION, grim: SCREEN, zbarimg: `echo https://example.com/x` });
  s.run('qr');
  assert.equal(s.read('wl-copy.stdin'), 'https://example.com/x');
  assert.equal(s.read('wl-copy.args'), '--sensitive\n');
  assert.match(s.read('argv.log'), /^zbarimg --raw -q -Sbinary -$/m);
  assert.deepEqual(s.pill(), ['island', 'capture', 'qr', 'QR code copied', '']);
});

test('qr with no code says No QR code found and copies nothing', (t) => {
  const s = scratch(t, { slurp: REGION, grim: SCREEN, zbarimg: 'exit 4' });
  s.run('qr');
  assert.equal(s.read('wl-copy.args'), null);
  assert.deepEqual(s.pill(), ['island', 'capture', 'qr', '', 'No QR code found']);
});

test("colour copies niri's pick as uppercase hex and gives the pill its swatch", (t) => {
  // niri 26.04 prints Option<PickedColor> as JSON: {"rgb":[r,g,b]} from 0 to 1, rounded as its own Hex line rounds.
  const s = scratch(t, { niri: `echo '{"rgb":[0.7843137254901961,0.2196078431372549,0.11764705882352941]}'` });
  s.run('colour');
  assert.match(s.read('argv.log'), /^niri msg --json pick-color$/m);
  assert.equal(s.read('wl-copy.stdin'), '#C8381E');
  assert.deepEqual(s.pill(), ['island', 'capture', 'colour', 'Copied', '#C8381E']);
});

test('colour cancelled (niri prints null) does nothing', (t) => {
  const s = scratch(t, { niri: `echo null` });
  s.run('colour');
  assert.equal(s.read('wl-copy.args'), null);
  assert.equal(s.pill(), null);
});

test('annotate hands the region to satty, which copies with wl-copy and shows no pill', (t) => {
  const s = scratch(t, { slurp: REGION, grim: SCREEN });
  s.run('annotate');
  assert.equal(s.read('satty.stdin'), 'screen-png\n');
  assert.match(s.read('argv.log'), /^satty --filename - --copy-command wl-copy /m);
  assert.equal(s.pill(), null);
});

test("annotate-clip hands the clipboard's image to satty", (t) => {
  const s = scratch(t, { 'wl-paste': `case "$*" in --list-types) echo image/png ;; '--type image/png') echo clip-png ;; *) exit 1 ;; esac` });
  s.run('annotate-clip');
  assert.equal(s.read('satty.stdin'), 'clip-png\n');
  assert.equal(s.pill(), null);
});

test('annotate-clip with no image in the clipboard opens nothing', (t) => {
  const s = scratch(t, { 'wl-paste': `case "$*" in --list-types) echo text/plain ;; *) echo words ;; esac` });
  s.run('annotate-clip');
  assert.equal(s.read('satty.stdin'), null);
});

// Real tesseract over a rendered line, so the eng+ben models, not a stub, prove what comes back.
function rendered(s, font, text) {
  const png = join(s.root, 'line.png');
  execFileSync('pango-view', ['-q', '--background=white', '--margin=20', `--font=${font}`, `--text=${text}`, '-o', png]);
  return `cat ${png}`;
}

test('real tesseract reads Ship v2 today off a rendered line', (t) => {
  const s = scratch(t, { slurp: REGION });
  writeFileSync(join(s.root, 'stubs', 'grim'), `#!/bin/bash\n${rendered(s, 'Noto Sans 40', 'Ship v2 today')}\n`);
  chmodSync(join(s.root, 'stubs', 'grim'), 0o755);
  s.run('ocr');
  assert.equal(s.read('wl-copy.stdin'), 'Ship v2 today');
  assert.deepEqual(s.pill(), ['island', 'capture', 'ocr', 'Text copied', '13 characters']);
});

test('real tesseract reads Bangla as Bangla, not Latin noise', (t) => {
  const s = scratch(t, { slurp: REGION });
  writeFileSync(join(s.root, 'stubs', 'grim'), `#!/bin/bash\n${rendered(s, 'Noto Sans Bengali 40', 'আমার সোনার বাংলা')}\n`);
  chmodSync(join(s.root, 'stubs', 'grim'), 0o755);
  s.run('ocr');
  const text = s.read('wl-copy.stdin');
  assert.match(text, /[ঀ-৿]{3}/);
  assert.doesNotMatch(text, /[A-Za-z]/);
});
