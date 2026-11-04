import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Every channel dots colorscheme reloads points into the temp dir, so nothing live is touched.
const dots = new URL('../../bin/dots', import.meta.url).pathname;

function isolated(state) {
  const env = Object.assign({}, process.env, {
    XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', DBUS_SESSION_BUS_ADDRESS: `unix:path=${state}/no-bus`,
    TMUX_TMPDIR: state, DCONF_PROFILE: `${state}/no-profile`, XDG_RUNTIME_DIR: state,
    DOTS_AGENT_HOME: `${state}/agents`,
  });
  delete env.TMUX;
  return env;
}

// The tree-sitter highlighter takes its faces when it is added, so a running kak drew the old keywords after `colorscheme dots` (m79 walk); kak's JSON UI prints each drawn word's face.
const hasKak = spawnSync('kak', ['-version']).status === 0;
test('a running kak draws the new colorscheme\'s keywords without a key press', { skip: !hasKak }, async (t) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-kak-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  const env = Object.assign(isolated(state), { XDG_CONFIG_HOME: join(state, 'config') });
  mkdirSync(join(state, 'config/kak/colors'), { recursive: true });
  symlinkSync(join(state, 'dots/theme-out/dots.kak'), join(state, 'config/kak/colors/dots.kak'));
  // Kakoune's own runtime adds the tree-sitter highlighter to every window with a filetype; mail.kak declares the option dots.kak sets for the mail list.
  writeFileSync(join(state, 'config/kak/kakrc'), 'declare-option str mail_keys\ncolorscheme dots\n');
  // The cursor starts on the first line and would split the word it sits on, so the keyword waits on the second.
  writeFileSync(join(state, 'probe.mjs'), "// probe\nimport { a } from './b.mjs';\n");
  assert.equal(spawnSync(dots, ['colorscheme', 'artboard'], { env }).status, 0);
  let out = '';
  const kak = spawn('kak', ['-ui', 'json', '-s', 'dots-kak-probe', join(state, 'probe.mjs')], { env, stdio: ['pipe', 'pipe', 'ignore'] });
  kak.stdout.on('data', (d) => { out += d; });
  t.after(() => kak.kill('SIGKILL'));
  // The last drawn colour of the word import.
  const keyword = () => {
    const draws = out.split('\n').filter((l) => l.includes('"method": "draw"'));
    const atoms = draws.length ? JSON.parse(draws.at(-1)).params[0].flat() : [];
    return atoms.find((a) => a.contents === 'import')?.face.fg;
  };
  const until = async (want) => {
    for (let i = 0; i < 60 && keyword() !== want; i++) await new Promise((r) => setTimeout(r, 50));
    return keyword();
  };
  assert.equal(await until('rgb:cf222e'), 'rgb:cf222e');
  assert.equal(spawnSync(dots, ['colorscheme', 'catppuccin-mocha'], { env }).status, 0);
  assert.equal(await until('rgb:cba6f7'), 'rgb:cba6f7');
});
