import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseToml } from './toml.mjs';
import { validateColorscheme } from './colorscheme.mjs';

const repo = new URL('../..', import.meta.url).pathname;
const cli = new URL('./colorscheme-render.mjs', import.meta.url).pathname;
const read = (name) => parseToml(readFileSync(join(repo, 'colorschemes', `${name}.toml`), 'utf8'));

// The approved board's colours: exact, uppercase, and they win over each project's own palette.
const BOARD = {
  'github-light': {
    title: 'GitHub Light', family: 'GitHub', variant: 'light',
    color: { paper: '#E8EAED', surface: '#FFFFFF', ink: '#1F2328', muted: '#59636E', line: '#D1D9E0', accent: '#0969DA' },
    syntax: { keyword: '#CF222E', function: '#8250DF', string: '#0A3069', type: '#953800', value: '#0550AE', variable: '#1F2328', comment: '#59636E', builtin: '#0550AE' },
  },
  'catppuccin-mocha': {
    title: 'Catppuccin Mocha', family: 'Catppuccin', variant: 'dark',
    color: { paper: '#11111B', surface: '#1E1E2E', ink: '#CDD6F4', muted: '#A6ADC8', line: '#313244', accent: '#89B4FA' },
    syntax: { keyword: '#CBA6F7', function: '#89B4FA', string: '#A6E3A1', type: '#F9E2AF', value: '#FAB387', variable: '#CDD6F4', comment: '#9399B2', builtin: '#F38BA8' },
  },
  'gruvbox-dark': {
    title: 'Gruvbox Dark', family: 'Gruvbox', variant: 'dark',
    color: { paper: '#1D2021', surface: '#282828', ink: '#EBDBB2', muted: '#A89984', line: '#3C3836', accent: '#83A598' },
    syntax: { keyword: '#FB4934', function: '#B8BB26', string: '#B8BB26', type: '#FABD2F', value: '#D3869B', variable: '#83A598', comment: '#928374', builtin: '#FE8019' },
  },
  'rose-pine-dawn': {
    title: 'Rosé Pine Dawn', family: 'Rosé Pine', variant: 'light',
    color: { paper: '#F2E9E1', surface: '#FAF4ED', ink: '#575279', muted: '#797593', line: '#DFDAD9', accent: '#907AA9' },
    syntax: { keyword: '#286983', function: '#D7827E', string: '#EA9D34', type: '#56949F', value: '#D7827E', variable: '#575279', comment: '#9893A5', builtin: '#B4637A' },
  },
};

const render = (t, name) => {
  const state = mkdtempSync(join(tmpdir(), 'dots-schemes-'));
  t.after(() => rmSync(state, { recursive: true, force: true }));
  execFileSync('node', [cli, name], { env: { ...process.env, XDG_STATE_HOME: state } });
  return join(state, 'dots/theme-out');
};

test('every colorscheme passes the check and is named for its file', () => {
  const names = readdirSync(join(repo, 'colorschemes')).filter((f) => f.endsWith('.toml')).map((f) => f.slice(0, -5));
  for (const name of Object.keys(BOARD)) assert.ok(names.includes(name), `${name}.toml exists`);
  for (const name of names) assert.equal(validateColorscheme(read(name)).name, name);
});

for (const [name, want] of Object.entries(BOARD)) {
  test(`${name} holds the board's colours`, () => {
    const doc = read(name);
    assert.equal(doc.meta.title, want.title);
    assert.equal(doc.meta.family, want.family);
    assert.equal(doc.meta.variant, want.variant);
    for (const [k, v] of Object.entries(want.color)) assert.equal(doc.color[k], v, `color.${k}`);
    for (const [k, v] of Object.entries(want.syntax)) assert.equal(doc.syntax[k], v, `syntax.${k}`);
  });

  test(`${name} renders a 1px ink and line frame, no shadow, and its mode`, (t) => {
    const out = render(t, name);
    const kdl = readFileSync(join(out, 'niri.kdl'), 'utf8').replace(/\s+/g, ' ');
    assert.ok(kdl.includes(`border { on width 1 active-color "${want.color.ink}" inactive-color "${want.color.line}" }`), kdl);
    assert.ok(kdl.includes('shadow { off }'));
    assert.equal(JSON.parse(readFileSync(join(out, 'shell.json'), 'utf8')).mode, want.variant);
  });
}

test('catppuccin-mocha reaches the terminal, the shell tokens and kakoune', (t) => {
  const out = render(t, 'catppuccin-mocha');
  const foot = readFileSync(join(out, 'foot.ini'), 'utf8');
  assert.match(foot, /\[colors-dark\][^[]*^background=1E1E2E$/m);
  assert.match(foot, /\[colors-dark\][^[]*^foreground=CDD6F4$/m);
  const shell = JSON.parse(readFileSync(join(out, 'shell.json'), 'utf8'));
  assert.equal(shell.color.paper, '#11111B');
  assert.equal(shell.color.surface, '#1E1E2E');
  assert.match(readFileSync(join(out, 'dots.kak'), 'utf8'), /^face global keyword rgb:cba6f7\+b$/m);
});

test('github-light colours the kakoune keyword', (t) => {
  const out = render(t, 'github-light');
  assert.match(readFileSync(join(out, 'dots.kak'), 'utf8'), /^face global keyword rgb:cf222e\+b$/m);
});

test('the licence file names each upstream project and its licence', () => {
  const text = readFileSync(join(repo, 'colorschemes/THIRD_PARTY_LICENSES'), 'utf8');
  for (const n of ['Catppuccin', 'Gruvbox', 'Rosé Pine', 'GitHub Primer']) assert.ok(text.includes(n), n);
  assert.ok(text.includes('MIT'));
});
