// The chezmoi source applied to a scratch home installs the reminders skill, which Claude may load on its own when Saiful asks to be reminded, and which asks before it cancels one.
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname.replace(/\/$/, '');
let root, home, skill;

before(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'reminders-skill-')));
  home = join(root, 'home');
  mkdirSync(home);
  writeFileSync(join(root, 'chezmoi.toml'), `sourceDir = "${repo}"\nmode = "symlink"\n[data]\n    machine = "test"\n`);
  const env = {
    PATH: process.env.PATH,
    HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'),
    XDG_DATA_HOME: join(home, '.local/share'),
    XDG_DATA_DIRS: '/usr/share',
    XDG_STATE_HOME: join(home, '.local/state'),
  };
  const applied = spawnSync('chezmoi', ['--config', join(root, 'chezmoi.toml'), '--source', repo, '--destination', home, 'apply', '--exclude', 'scripts,encrypted'], { env, encoding: 'utf8' });
  assert.equal(applied.status, 0, applied.stderr);
  skill = join(home, '.claude/skills/reminders/SKILL.md');
});

after(() => rmSync(root, { recursive: true, force: true }));

test('the skill is installed, named reminders, and Claude may load it on its own', () => {
  assert.ok(existsSync(skill), skill);
  const text = readFileSync(skill, 'utf8');
  const front = text.match(/^---\n([\s\S]*?)\n---\n/)[1];
  assert.match(front, /^name: reminders$/m);
  assert.doesNotMatch(front, /disable-model-invocation/);
  const description = front.match(/^description: (.+)$/m)[1];
  assert.ok(description.includes('remind me'), description);
  assert.ok(description.includes('what reminders'), description);
});

test('the skill names the three commands and the time forms add takes', () => {
  const text = readFileSync(skill, 'utf8');
  for (const s of ['reminder add', 'reminder list', 'reminder list --json', 'reminder rm', '`20m`', '`1h30m`', '`17:30`']) {
    assert.ok(text.includes(s), s);
  }
});

test('the skill asks Saiful before any reminder rm', () => {
  const text = readFileSync(skill, 'utf8');
  assert.ok(text.includes('Never run `reminder rm` until Saiful says yes to that reminder'));
});

test('the skill asks, then waits, and only then removes, in that order', () => {
  const text = readFileSync(skill, 'utf8');
  const steps = ['Run `reminder list`', 'Ask him', 'Then stop and wait for his answer.', 'After his yes, run `reminder rm <id>`'].map((x) => text.indexOf(x));
  assert.ok(steps.every((at) => at >= 0), String(steps));
  assert.deepEqual([...steps].sort((a, b) => a - b), steps);
});

// Unquoted, bash turns "pay Rubel $50" into "pay Rubel 0" and drops all after a #.
test('the skill puts the text in single quotes', () => {
  const text = readFileSync(skill, 'utf8');
  assert.ok(text.includes("reminder add 5m 'stretch'"));
  assert.ok(text.includes('Put the text in single quotes'));
});

// At 10:00, "tomorrow at 17:30" given as 17:30 would ring today.
test('the skill counts hours for a named day the clock form would ring too soon', () => {
  const text = readFileSync(skill, 'utf8');
  assert.ok(text.includes('When he names tomorrow and that time is still ahead today'));
});
