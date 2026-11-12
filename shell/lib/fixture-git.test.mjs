import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

// A test's fixture git that reads the machine's global config runs its hooks too, and the agent push guard among them refused update.test.mjs's seed push in every agent session (m85, 677ed962).
const root = new URL('../..', import.meta.url).pathname;
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' })
  .split('\n')
  .filter((f) => /^(tests|shell\/lib)\/.*\.mjs$/.test(f) && f !== 'shell/lib/fixture-git.test.mjs');

const VERB = '(?:init|clone|commit|push)';
// spawn('git', [... 'init'), git(cwd, 'init'), ['git', 'init'] as pass git takes it, 'git -C x init' in a shell line, and `${GIT} commit` for a git command kept in a constant.
const WRITES = [
  new RegExp(`['"\`]git['"\`]\\s*,\\s*\\[[^\\]]*?['"\`]${VERB}['"\`]`, 's'),
  new RegExp(`\\bgit\\([^)]*?['"\`]${VERB}['"\`]`, 's'),
  new RegExp(`['"\`]git['"\`]\\s*,\\s*['"\`]${VERB}['"\`]`),
  new RegExp(`\\bgit(?:\\s+-[cC]\\s+\\S+)*\\s+${VERB}\\b`),
  new RegExp(`\\$\\{\\w+\\}\\s+${VERB}\\b`),
];

const code = (text) =>
  text
    .split('\n')
    .filter((l) => !/^\s*\/\//.test(l))
    .join('\n');

export const runsFixtureGit = (text) => {
  const c = code(text);
  return WRITES.slice(0, 4).some((re) => re.test(c)) || (/['"`]git\s/.test(c) && WRITES[4].test(c));
};

// The file itself or a module it imports by a relative path sets GIT_CONFIG_GLOBAL.
const imports = (f, text) => [...text.matchAll(/from\s+['"](\.{1,2}\/[^'"]+)['"]/g)].map((m) => join(dirname(f), m[1]));
const setsGlobal = (f, text) => /GIT_CONFIG_GLOBAL/.test(text) || imports(f, text).some((i) => existsSync(join(root, i)) && /GIT_CONFIG_GLOBAL/.test(readFileSync(join(root, i), 'utf8')));

test('the matcher finds fixture git in every spelling the tests have used, and leaves read-only git alone', () => {
  const writes = [
    "spawnSync('git', ['-c', 'user.name=t', 'commit', '-qm', 'x'], { cwd })",
    "git(home, 'init', '-q', '-b', 'main', up);",
    "x('pass', ['git', 'init']);",
    "sh(root, 'git init -q --bare -b main origin.git');",
    "sh(root, 'git -C seed push -q origin main');",
    "const GIT = 'git -c user.name=t -c user.email=t@t';\nsh(seed, `${GIT} commit -qm two`);",
    "const git = (...a) => spawnSync('git', ['-C', repo, ...a], { env });\ngit('init', '-q', '-b', 'main');",
  ];
  for (const w of writes) assert.ok(runsFixtureGit(w), w);
  const reads = [
    "execFileSync('git', ['ls-files', '--cached'], { cwd: root })",
    "run('git', ['-C', repo, 'status', '--porcelain'])",
    "spawnSync('git', ['config', '--file', gitConfig, '--get', key])",
    "// a git push from the fixture would run the hooks",
  ];
  for (const r of reads) assert.ok(!runsFixtureGit(r), r);
});

test('a test that runs fixture git sets GIT_CONFIG_GLOBAL', () => {
  const found = files.filter((f) => {
    const text = readFileSync(join(root, f), 'utf8');
    return runsFixtureGit(text) && !setsGlobal(f, text);
  });
  assert.deepEqual(found, []);
});
