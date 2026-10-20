// The apply's skills step on a scratch home, cloning a local fixture repo through DOTS_SKILLS_REPO, so no run reaches the private repo.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const script = readFileSync(join(repo, 'home/.chezmoiscripts/run_onchange_after_31-skills.sh.tmpl'), 'utf8');

function git(cwd, ...args) {
  const r = spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
}

// An upstream repo holding skills/<name>/SKILL.md for each name, desktop among them as the real one may.
function upstream(home, names) {
  const up = join(home, 'upstream');
  for (const name of names) {
    mkdirSync(join(up, 'skills', name), { recursive: true });
    writeFileSync(join(up, 'skills', name, 'SKILL.md'), `# ${name}\n`);
  }
  git(home, 'init', '-q', '-b', 'main', up);
  git(up, 'add', '.');
  git(up, 'commit', '-qm', 'skills');
  return up;
}

function scratch({ loggedIn }) {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-skills-')));
  if (loggedIn) {
    mkdirSync(join(home, '.config/gh'), { recursive: true });
    writeFileSync(join(home, '.config/gh/hosts.yml'), 'github.com:\n    user: saifulapm\n');
  }
  return home;
}

function render(home) {
  const env = { PATH: process.env.PATH, HOME: home };
  const r = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: script, encoding: 'utf8', env });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
}

function apply(home, up) {
  const env = { PATH: process.env.PATH, HOME: home, DOTS_SKILLS_REPO: up ?? join(home, 'no-such-repo') };
  return spawnSync('bash', ['-c', render(home)], { encoding: 'utf8', env });
}

test('before dots secrets the step says it skipped, clones nothing and exits 0', () => {
  const home = scratch({ loggedIn: false });
  const r = apply(home, upstream(home, ['pdf']));
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /skills: skipped until dots secrets/);
  assert.equal(existsSync(join(home, '.local/src/skills')), false);
  assert.equal(existsSync(join(home, '.claude/skills/pdf')), false);
});

test('once gh is logged in each skill is linked into both folders', () => {
  const home = scratch({ loggedIn: true });
  const r = apply(home, upstream(home, ['pdf', 'eli5']));
  assert.equal(r.status, 0, r.stderr);
  for (const dir of ['.claude/skills', '.agents/skills']) {
    assert.equal(readlinkSync(join(home, dir, 'pdf')), `${home}/.local/src/skills/skills/pdf`, dir);
    assert.equal(readlinkSync(join(home, dir, 'eli5')), `${home}/.local/src/skills/skills/eli5`, dir);
  }
});

// The dotfiles ship desktop and diagnose-crash themselves, and their copy wins in both folders.
test('a skill the dotfiles ship is not linked from the skills repo', () => {
  const home = scratch({ loggedIn: true });
  const r = apply(home, upstream(home, ['desktop', 'diagnose-crash', 'pdf']));
  assert.equal(r.status, 0, r.stderr);
  for (const dir of ['.claude/skills', '.agents/skills']) {
    assert.equal(existsSync(join(home, dir, 'desktop')), false, dir);
    assert.equal(existsSync(join(home, dir, 'diagnose-crash')), false, dir);
  }
});

// workflow install writes real folders into the same two places.
test('a folder another installer wrote is left as it is', () => {
  const home = scratch({ loggedIn: true });
  mkdirSync(join(home, '.claude/skills/tdd'), { recursive: true });
  writeFileSync(join(home, '.claude/skills/tdd/SKILL.md'), 'workflow\n');
  const r = apply(home, upstream(home, ['tdd']));
  assert.equal(r.status, 0, r.stderr);
  assert.equal(lstatSync(join(home, '.claude/skills/tdd')).isDirectory(), true);
  assert.equal(readFileSync(join(home, '.claude/skills/tdd/SKILL.md'), 'utf8'), 'workflow\n');
});

test('after a pull, a new skill is linked and a dropped one unlinked', () => {
  const home = scratch({ loggedIn: true });
  const up = upstream(home, ['pdf', 'eli5']);
  assert.equal(apply(home, up).status, 0);
  rmSync(join(up, 'skills/eli5'), { recursive: true });
  mkdirSync(join(up, 'skills/vite'));
  writeFileSync(join(up, 'skills/vite/SKILL.md'), '# vite\n');
  git(up, 'add', '-A');
  git(up, 'commit', '-qm', 'swap');
  git(join(home, '.local/src/skills'), 'pull', '-q', '--ff-only');
  const r = apply(home, up);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readlinkSync(join(home, '.claude/skills/vite')), `${home}/.local/src/skills/skills/vite`);
  assert.equal(existsSync(join(home, '.claude/skills/eli5')), false);
  assert.throws(() => lstatSync(join(home, '.agents/skills/eli5')));
});

// run_onchange re-runs a script only when its rendered text changes.
test('the script re-renders once gh is logged in and once the clone gains a skill, and not otherwise', () => {
  const home = scratch({ loggedIn: false });
  const before = render(home);
  assert.equal(render(home), before);
  mkdirSync(join(home, '.config/gh'), { recursive: true });
  writeFileSync(join(home, '.config/gh/hosts.yml'), 'github.com:\n');
  const loggedIn = render(home);
  assert.notEqual(loggedIn, before);
  mkdirSync(join(home, '.local/src/skills/skills/pdf'), { recursive: true });
  assert.notEqual(render(home), loggedIn);
});
