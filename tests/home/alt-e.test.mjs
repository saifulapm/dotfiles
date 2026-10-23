// Alt+E in a throwaway tmux running fish with only the repo's function and bind, against a stub of pxy's
// chat endpoint on a free port. No test connects to 4100, where the real pxy spends real quota.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createServer } from 'node:http';
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const run = promisify(execFile);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const repo = new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
const fn = join(repo, 'home/dot_config/fish/functions/_dots_ai_cmd.fish');
const bind = join(repo, 'home/dot_config/fish/conf.d/alt-e.fish');
const typed = 'list files bigger than 100 MB here';

// handler(req, res) answers the stub's requests; null means nothing listens on the port.
async function stub(t, handler) {
  const server = createServer(handler ?? (() => {}));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();
  if (handler) t.after(() => { server.closeAllConnections(); server.close(); });
  else await new Promise((r) => server.close(r));
  assert.notEqual(port, 4100);
  return `http://127.0.0.1:${port}`;
}

const answer = (content) => (req, res) => {
  req.resume();
  req.on('end', () => {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ choices: [{ message: { role: 'assistant', content } }] }));
  });
};

// Starts fish in tmux with DOTS_AI_URL at url, types the task and presses M-e. Returns the scratch dir,
// a screen reader and the time M-e went in.
async function altE(t, url) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'alt-e-')));
  const home = join(root, 'home');
  mkdirSync(home);
  const sock = `dots-alt-e-${process.pid}-${Math.random().toString(36).slice(2)}`;
  const env = { ...process.env };
  delete env.TMUX;
  const tmux = async (...a) => (await run('tmux', ['-L', sock, '-f', '/dev/null', ...a], { env, encoding: 'utf8' })).stdout;
  t.after(async () => { try { await tmux('kill-server'); } catch {} rmSync(root, { recursive: true, force: true }); });
  await tmux('new-session', '-d', '-x', '250', '-y', '30', '-c', root,
    'env', `HOME=${home}`, `XDG_CONFIG_HOME=${home}/.config`, `XDG_DATA_HOME=${home}/.local/share`, `DOTS_AI_URL=${url}`,
    'fish', '--no-config', '-C', `function fish_prompt; echo -n '$ '; end; set -g fish_greeting; source ${fn}; source ${bind}`);
  const screen = async () => (await tmux('capture-pane', '-p')).split('\n').map((l) => l.trimEnd()).filter(Boolean);
  const until = async (ok, ms) => {
    let lines = [];
    for (const end = Date.now() + ms; Date.now() < end; await sleep(100)) {
      lines = await screen();
      if (ok(lines)) break;
    }
    return lines;
  };
  await until((l) => l.at(-1) === '$', 10000);
  await tmux('send-keys', '-l', typed);
  await until((l) => l.at(-1) === `$ ${typed}`, 5000);
  await tmux('send-keys', 'M-e');
  return { root, screen, until, pressed: Date.now() };
}

const errorLines = (lines) => lines.filter((l) => l.startsWith('Alt+E:'));
const failed = (lines) => errorLines(lines).length > 0;

// Exactly one Alt+E line prints under the typed line, and the prompt under it holds the typed line again.
function assertRestored(lines) {
  const at = lines.findIndex((l) => l.startsWith('Alt+E:'));
  assert.equal(errorLines(lines).length, 1, lines.join('\n'));
  assert.equal(lines[at - 1], `$ ${typed}`, lines.join('\n'));
  assert.equal(lines.at(-1), `$ ${typed}`, lines.join('\n'));
}

test('Alt+E replaces the typed task with the command pxy answers', async (t) => {
  const { until } = await altE(t, await stub(t, answer('find . -size +100M')));
  const lines = await until((l) => l.at(-1) === '$ find . -size +100M', 5000);
  assert.equal(lines.at(-1), '$ find . -size +100M');
});

test('Alt+E only puts the command on the line, it does not run it', async (t) => {
  const marker = join(realpathSync(mkdtempSync(join(tmpdir(), 'alt-e-ran-'))), 'ran');
  t.after(() => rmSync(join(marker, '..'), { recursive: true, force: true }));
  const { until } = await altE(t, await stub(t, answer(`touch ${marker}`)));
  const lines = await until((l) => l.at(-1) === `$ touch ${marker}`, 5000);
  assert.equal(lines.at(-1), `$ touch ${marker}`);
  await sleep(500);
  assert.equal(existsSync(marker), false);
});

test('Alt+E strips a markdown fence around the answer', async (t) => {
  const { until } = await altE(t, await stub(t, answer('```sh\nfind . -size +100M\n```\n')));
  const lines = await until((l) => l.at(-1) === '$ find . -size +100M', 5000);
  assert.equal(lines.at(-1), '$ find . -size +100M');
});

test('Alt+E keeps one line of the answer, without ESC or bidi marks', async (t) => {
  const { screen, until } = await altE(t, await stub(t, answer('find .\x1b[31m -size‮ +100M\nrm -rf ~')));
  await until((l) => l.at(-1) === '$ find .[31m -size +100M', 5000);
  const lines = await screen();
  assert.equal(lines.at(-1), '$ find .[31m -size +100M');
  assert.equal(lines.some((l) => l.includes('rm -rf')), false, lines.join('\n'));
});

test('Alt+E with nothing listening keeps the typed line and prints one error', async (t) => {
  const { until } = await altE(t, await stub(t, null));
  assertRestored(await until(failed, 5000));
});

test('Alt+E gives the typed line back after 20 s when pxy never answers', { timeout: 30000 }, async (t) => {
  const { until, pressed } = await altE(t, await stub(t, (req) => req.resume()));
  const lines = await until(failed, 25000);
  const waited = Date.now() - pressed;
  assertRestored(lines);
  assert.ok(waited >= 19000 && waited <= 22000, `back after ${waited} ms`);
});

test('Alt+E on an HTTP error shows pxy\'s message on one clean line', async (t) => {
  const message = 'all providers failed\n‮\x1b[2J' + 'x'.repeat(300);
  const { until } = await altE(t, await stub(t, (req, res) => {
    req.resume();
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: { message } }));
  }));
  const lines = await until(failed, 5000);
  assertRestored(lines);
  assert.equal(errorLines(lines)[0], 'Alt+E: all providers failed [2J' + 'x'.repeat(176));
});
