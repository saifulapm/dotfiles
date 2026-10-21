import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, writeFileSync, rmSync, cpSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const cli = new URL('./theme-render.mjs', import.meta.url).pathname;

test('renders every fragment into XDG_STATE_HOME/dots/theme-out', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-theme-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  execFileSync('node', [cli, 'paper'], { env: { ...process.env, XDG_STATE_HOME: state } });
  const out = join(state, 'dots/theme-out');
  const shell = JSON.parse(readFileSync(join(out, 'shell.json'), 'utf8'));
  assert.equal(shell.name, 'paper');
  assert.equal(shell.color.paper, '#F1E9D8');
  assert.match(readFileSync(join(out, 'foot.ini'), 'utf8'), /^background=FAF6EC$/m);
  const config = join(state, 'config.kdl');
  writeFileSync(config, `include "${join(out, 'niri.kdl')}"\n`);
  execFileSync('niri', ['validate', '-c', config], { stdio: 'pipe' });
});

test('renders the app fragments and no kitty or opencode file', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-theme-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  execFileSync('node', [cli, 'blueprint'], { env: { ...process.env, XDG_STATE_HOME: state } });
  const names = readdirSync(join(state, 'dots/theme-out'));
  for (const f of ['tmux.conf', 'dots.kak', 'helix.toml', 'yazi-theme.toml', 'colors.fish', 'gtk.css', 'gtk-settings.ini', 'chromium.json']) {
    assert.ok(names.includes(f), f);
  }
  assert.deepEqual(names.filter((n) => /kitty|opencode/i.test(n)), []);
});

test('an unknown theme exits non-zero and names it', () => {
  assert.throws(
    () => execFileSync('node', [cli, 'nope'], { stdio: 'pipe' }),
    (e) => /theme nope/.test(e.stderr.toString()),
  );
});

test('every theme renders a niri fragment niri accepts', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-theme-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  for (const name of ['paper', 'artboard', 'blueprint']) {
    execFileSync('node', [cli, name], { env: { ...process.env, XDG_STATE_HOME: state } });
    const config = join(state, 'config.kdl');
    writeFileSync(config, `include "${join(state, 'dots/theme-out/niri.kdl')}"\n`);
    execFileSync('niri', ['validate', '-c', config], { stdio: 'pipe' });
  }
});

test('themes.json lists every valid theme, paper first, and skips a broken one', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'dots-themes-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const repo = new URL('../..', import.meta.url).pathname;
  cpSync(join(repo, 'shell/lib'), join(root, 'shell/lib'), { recursive: true });
  cpSync(join(repo, 'themes'), join(root, 'themes'), { recursive: true });
  mkdirSync(join(root, 'themes/broken'));
  writeFileSync(join(root, 'themes/broken/theme.toml'), '[meta]\nname = "broken"\nmode = "dim"\n');
  const state = join(root, 'state');
  execFileSync('node', [join(root, 'shell/lib/theme-render.mjs'), 'paper'], { env: { ...process.env, XDG_STATE_HOME: state } });
  const themes = JSON.parse(readFileSync(join(state, 'dots/theme-out/themes.json'), 'utf8'));
  assert.deepEqual(themes.map((x) => x.name), ['paper', 'artboard', 'blueprint']);
  assert.deepEqual(Object.keys(themes[2]), ['name', 'mode', 'color', 'syntax', 'primitive', 'paper', 'type', 'niri']);
  assert.equal(themes[2].color.paper, '#0C1A2E');
  assert.equal(themes[2].primitive.frame, 'glow');
  assert.equal(themes[1].paper.dot, '#B4BAC4');
  assert.equal(themes[2].paper.minor, 16);
  assert.equal(themes[2].type.voice, 'bracket');
  assert.equal(themes[1].niri.ring_color, '#3D5AFE');
  assert.equal(themes[0].niri.border_inactive, '#575653');
});

// Each theme's kak-mail list colours and key strip as its KakMail board draws them; a hex a token does not carry is the board's own.
const MAIL = {
  paper: {
    MailDate: 'rgb:575653',
    MailSender: 'rgb:2c4a9a',
    MailSubject: 'rgb:1c1915',
    MailUnread: 'default,default+b',
    MailCursor: 'rgb:faf6ec,rgb:1c1915+b',
    MailStrip: 'rgb:575653,rgb:faf6ec',
    MailKey: 'rgb:1c1915,rgb:faf6ec+b',
    keys: '{MailKey}↵{MailStrip} OPEN · {MailKey}R{MailStrip} REPLY · {MailKey}E{MailStrip} ARCHIVE · {MailKey}S{MailStrip} SCREENER · {MailKey}F{MailStrip} FEED · {MailKey}?{MailStrip} HELP',
  },
  artboard: {
    MailDate: 'rgb:c2410c',
    MailSender: 'rgb:3d5afe',
    MailSubject: 'rgb:15171b',
    MailUnread: 'default,default+b',
    MailCursor: 'rgb:2638c9,rgb:eef1ff+b',
    MailStrip: 'rgb:57606a,rgb:ffffff',
    MailKey: 'rgb:15171b,rgb:ffffff',
    keys: '{MailKey}↵{MailStrip} open · {MailKey}r{MailStrip} reply · {MailKey}e{MailStrip} archive · {MailKey}s{MailStrip} screener · {MailKey}f{MailStrip} feed · {MailKey}?{MailStrip} help',
  },
  blueprint: {
    MailDate: 'rgb:80a4c2',
    MailSender: 'rgb:7fe3f0',
    MailSubject: 'rgb:d6f4f8',
    MailUnread: 'default,default+b',
    MailCursor: 'rgb:0a1526,rgb:7fe3f0+b',
    MailStrip: 'rgb:80a4c2,rgb:0a1526',
    MailKey: 'rgb:7fe3f0,rgb:0a1526',
    keys: '{MailKey}[↵]{MailStrip} OPEN · {MailKey}[R]{MailStrip} REPLY · {MailKey}[E]{MailStrip} ARCHIVE · {MailKey}[S]{MailStrip} SCREENER · {MailKey}[F]{MailStrip} FEED · {MailKey}[?]{MailStrip} HELP',
  },
};

test('dots.kak defines the kak-mail faces and key strip in each theme\'s colours', (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-theme-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  for (const [name, want] of Object.entries(MAIL)) {
    execFileSync('node', [cli, name], { env: { ...process.env, XDG_STATE_HOME: state } });
    const kak = readFileSync(join(state, 'dots/theme-out/dots.kak'), 'utf8').split('\n');
    const got = Object.fromEntries(
      kak.map((l) => l.match(/^face global (Mail\w+) (.+)$/)).filter(Boolean).map((m) => [m[1], m[2]]),
    );
    const keys = kak.find((l) => l.startsWith('set-option global mail_keys '));
    got.keys = keys?.slice("set-option global mail_keys '".length, -1);
    assert.deepEqual(got, want, name);
  }
});
