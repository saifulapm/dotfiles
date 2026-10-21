// One PHP, Fedora's 8.5: the .test wildcard's caddy and php-fpm run on a scratch home and free ports, since the live ones own 443 and 9085.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');
const units = 'home/dot_config/systemd/user';
const has = (tool) => spawnSync('sh', ['-c', `command -v ${tool}`]).status === 0;
const missing = !has('caddy') ? 'caddy is not installed' : !has('/usr/sbin/php-fpm') && 'php-fpm is not installed';

const freePort = () => new Promise((resolve) => {
  const s = createServer().listen(0, '127.0.0.1', () => {
    const { port } = s.address();
    s.close(() => resolve(port));
  });
});

async function until(ok, ms) {
  for (const end = Date.now() + ms; Date.now() < end; await new Promise((r) => setTimeout(r, 100))) if (ok()) return;
  throw new Error(`not ready after ${ms} ms`);
}

test('caddy sends .test to php-fpm on 9085, which a socket starts and 10 idle minutes stop', () => {
  assert.match(read('home/dot_config/caddy/Caddyfile.tmpl'), /^\tphp_fastcgi 127\.0\.0\.1:9085$/m);
  assert.match(read(`${units}/php-fpm-proxy.socket`), /^ListenStream=127\.0\.0\.1:9085$/m);
  const proxy = read(`${units}/php-fpm-proxy.service`);
  assert.match(proxy, /^Requires=php-fpm\.service$/m);
  assert.match(proxy, /^ExecStart=\/usr\/lib\/systemd\/systemd-socket-proxyd --exit-idle-time=10min 127\.0\.0\.1:39085$/m);
  const fpm = read(`${units}/php-fpm.service`);
  assert.match(fpm, /^StopWhenUnneeded=true$/m);
  assert.match(fpm, /^ExecStart=\/usr\/sbin\/php-fpm --nodaemonize --fpm-config %h\/\.config\/php-fpm\/dev\.conf$/m);
  assert.match(read('home/dot_config/php-fpm/dev.conf.tmpl'), /^listen = 127\.0\.0\.1:39085$/m);
  assert.equal(read(`${units}/sockets.target.wants/symlink_php-fpm-proxy.socket`).trim(), '../php-fpm-proxy.socket');
});

test('a folder with public/ is served on PHP 8.5, one without it gets a 404, and only on 127.0.0.1', { skip: missing }, async (t) => {
  const home = realpathSync(mkdtempSync(join(tmpdir(), 'dots-sites-')));
  const env = {
    PATH: `${home}/stubs:/usr/bin:/bin`, HOME: home,
    XDG_CONFIG_HOME: join(home, '.config'), XDG_DATA_HOME: join(home, '.local/share'), XDG_CACHE_HOME: join(home, '.cache'),
  };
  const render = (f) => {
    const r = spawnSync('chezmoi', ['--config', join(home, 'none.toml'), '--source', repo, 'execute-template'], { input: read(f), encoding: 'utf8', env });
    assert.equal(r.status, 0, r.stderr);
    return r.stdout;
  };
  const [http, https, fpm] = [await freePort(), await freePort(), await freePort()];
  // caddy installs a new CA into the system's trust through sudo; the stub records any such call.
  mkdirSync(join(home, 'stubs'));
  writeFileSync(join(home, 'stubs/sudo'), '#!/bin/sh\necho "$*" >> "$HOME/sudo.log"\nexit 1\n', { mode: 0o755 });
  mkdirSync(join(home, '.local/state/php-fpm'), { recursive: true });
  mkdirSync(join(home, 'Codes/site/public'), { recursive: true });
  mkdirSync(join(home, 'Codes/nopublic'), { recursive: true });
  writeFileSync(join(home, 'Codes/site/public/index.php'), '<?php echo PHP_VERSION;');
  writeFileSync(join(home, 'Codes/nopublic/index.php'), '<?php echo "served";');
  mkdirSync(join(home, 'Codes/site/storage/app/public'), { recursive: true });
  writeFileSync(join(home, 'Codes/site/storage/app/public/index.php'), '<?php echo "nested";');
  // The live caddy owns the admin port and the live socket proxy owns 9085, so the copy talks to its php-fpm directly; its scratch CA stays out of the system trust.
  writeFileSync(join(home, 'Caddyfile'), render('home/dot_config/caddy/Caddyfile.tmpl')
    .replace('{\n', '{\n\tadmin off\n\tskip_install_trust\n').replace('http_port 38080', `http_port ${http}`).replace('https_port 38443', `https_port ${https}`)
    .replace('127.0.0.1:9085', `127.0.0.1:${fpm}`));
  writeFileSync(join(home, 'dev.conf'), render('home/dot_config/php-fpm/dev.conf.tmpl').replace('127.0.0.1:39085', `127.0.0.1:${fpm}`));

  const procs = [
    spawn('/usr/sbin/php-fpm', ['--nodaemonize', '--fpm-config', join(home, 'dev.conf')], { env, stdio: 'ignore' }),
    spawn('caddy', ['run', '--config', join(home, 'Caddyfile'), '--adapter', 'caddyfile'], { env, stdio: 'ignore' }),
  ];
  t.after(() => procs.forEach((p) => p.kill()));
  const get = (name) => spawnSync('curl', ['-sk', '--max-time', '10', '--resolve', `${name}.test:${https}:127.0.0.1`, '-w', '\n%{http_code}', `https://${name}.test:${https}/`], { encoding: 'utf8' }).stdout;
  await until(() => get('site').endsWith('\n200'), 15000);

  assert.match(get('site'), /^8\.5\.\d+\n200$/);
  assert.equal(get('nopublic'), '\n404');
  assert.ok(!existsSync(join(home, 'sudo.log')), 'caddy asked sudo to trust its scratch CA');
  // HTTP/2 lets a client put a slash in the host, which would make {labels.1} a path to a deeper public/, such as Laravel's uploads.
  const forged = spawnSync('curl', ['-sk', '--http2', '--max-time', '10', '--resolve', `site.test:${https}:127.0.0.1`, '-H', 'Host: site/storage/app.test', '-w', '\n%{http_code}', `https://site.test:${https}/`], { encoding: 'utf8' }).stdout;
  assert.doesNotMatch(forged, /nested|\n200$/);
  // The sockets in front of caddy listen on 127.0.0.1 only, so caddy's own ports must not answer from the network either.
  const bound = spawnSync('ss', ['-Hltun', `( sport = :${http} or sport = :${https} )`], { encoding: 'utf8' }).stdout.trim().split('\n');
  assert.ok(bound.length >= 2, bound.join('\n'));
  assert.deepEqual(bound.filter((l) => !/\s127\.0\.0\.1:\d+\s/.test(l)), []);
});

test('nothing ships or keeps Remi\'s PHP collections, their fpm units or the shims that picked them', () => {
  assert.doesNotMatch(read('packages.toml'), /remi|"php8\d/);
  const shipped = readdirSync(join(repo, units), { recursive: true }).filter((f) => /php8\d/.test(f));
  assert.deepEqual(shipped, []);
  assert.deepEqual(readdirSync(join(repo, 'home/dot_config/php-fpm')), ['dev.conf.tmpl']);
  // A machine that had them loses the files the apply once linked there.
  const removed = read('home/.chezmoiremove').split('\n');
  for (const v of ['83', '84']) {
    for (const u of [`php${v}-fpm.service`, `php${v}-fpm-proxy.service`, `php${v}-fpm-proxy.socket`, `sockets.target.wants/php${v}-fpm-proxy.socket`]) {
      assert.ok(removed.includes(`.config/systemd/user/${u}`), u);
    }
    assert.ok(removed.includes(`.config/php-fpm/php${v}-dev.conf`), `php${v}-dev.conf`);
  }
});

// The dotfiles bin dir comes first on PATH, as fish and mise put it.
test('a project pinned to 8.3 by .php-version still runs on 8.5', { skip: !has('/usr/bin/php') && 'php is not installed' }, () => {
  const dir = realpathSync(mkdtempSync(join(tmpdir(), 'dots-pinned-')));
  writeFileSync(join(dir, '.php-version'), '8.3\n');
  const r = spawnSync('php', ['-r', 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'], { cwd: dir, encoding: 'utf8', env: { PATH: `${repo}bin:/usr/bin:/bin`, HOME: dir } });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, '8.5');
  assert.equal(r.stderr, '');
});
