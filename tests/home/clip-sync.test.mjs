// Clipboard sync between the machines and the phone, as v1 had it: a socket per connection on 9411, a watcher that pushes each copy, and 10.99.99.99 for the phone.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const read = (f) => readFileSync(join(repo, f), 'utf8');
const units = 'home/dot_config/systemd/user';

test('the endpoint listens on loopback for tailscale serve and on the VIP for the phone, one handler per connection', () => {
  const socket = read(`${units}/dots-clip-serve.socket`);
  assert.deepEqual(socket.match(/^ListenStream=.*$/gm), ['ListenStream=127.0.0.1:9411', 'ListenStream=10.99.99.99:9411']);
  assert.match(socket, /^FreeBind=yes$/m);
  assert.match(socket, /^Accept=yes$/m);
  assert.equal(read(`${units}/sockets.target.wants/symlink_dots-clip-serve.socket`).trim(), '../dots-clip-serve.socket');
  const handler = read(`${units}/dots-clip-serve@.service`);
  assert.match(handler, /^ExecStart=%h\/\.local\/bin\/dots-clip-serve$/m);
  assert.match(handler, /^StandardInput=socket$/m);
  assert.match(handler, /^RuntimeMaxSec=30$/m);
});

test('niri starts the watcher, which pushes each text copy and publishes the endpoint on the tailnet\'s port 80', () => {
  const unit = read(`${units}/dots-clip-sync.service`);
  assert.match(unit, /^ExecStart=\/usr\/bin\/wl-paste --type text --watch %h\/\.local\/bin\/dots-clip-push$/m);
  assert.match(unit, /^ExecStartPost=-\/usr\/bin\/timeout 30 \/usr\/bin\/tailscale serve --bg --yes --http=80 http:\/\/127\.0\.0\.1:9411$/m);
  assert.match(read('home/dot_config/niri/config.kdl'), /^spawn-at-startup "systemctl" "--user" "start" "dots-clip-sync\.service"$/m);
  const links = read('home/.chezmoiscripts/run_onchange_after_15-clip.sh.tmpl');
  for (const name of ['dots-clip-store', 'dots-clip-serve', 'dots-clip-push']) assert.ok(links.includes(`bin/${name}" | quote }} "$HOME/.local/bin/${name}"`), name);
});

test('the VIP sits on loopback from boot, the tailnet alone reaches 9411, and tailscale up advertises the route', () => {
  assert.match(read('system/systemd/dots-clip-vip.service'), /^ExecStart=\/usr\/sbin\/ip addr replace 10\.99\.99\.99\/32 dev lo$/m);
  const script = read('home/.chezmoiscripts/run_onchange_after_15-clip-vip.sh.tmpl');
  assert.match(script, /root install -D -m 0644 .*dots-clip-vip\.service.* \/etc\/systemd\/system\/dots-clip-vip\.service/);
  assert.match(script, /root systemctl enable dots-clip-vip\.service/);
  const state = script.indexOf('root firewall-cmd --state');
  assert.ok(state > 0 && state < script.indexOf('--add-rich-rule'), 'it asks firewalld first, so a container skips it');
  assert.ok(script.includes(`'rule family="ipv4" source address="100.64.0.0/10" port port="9411" protocol="tcp" accept'`));
  assert.match(read('bin/dots'), /^  sudo tailscale up --operator=\$USER --advertise-routes=10\.99\.99\.99\/32$/m);
});
