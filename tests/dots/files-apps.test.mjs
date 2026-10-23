// dots-files-apps on scratch XDG dirs: which apps declare the files' type, one launch with every file, and a default written through a symlinked mimeapps.list.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const bin = new URL('../../bin/dots-files-apps', import.meta.url).pathname;
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const MIMEAPPS = '[Default Applications]\ntext/plain=org.gnome.TextEditor.desktop\nimage/jpeg=other.desktop\n\n[Added Associations]\nimage/png=other.desktop;\n';

function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'files-apps-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const apps = join(root, 'data/applications');
  const share = join(root, 'share');
  const config = join(root, 'config');
  const dotfiles = join(root, 'dotfiles');
  for (const d of [apps, share, config, dotfiles]) mkdirSync(d, { recursive: true });
  // Only the scratch entries are listed, but the type of a file still comes from the system's MIME database.
  symlinkSync('/usr/share/mime', join(share, 'mime'));
  const args = join(root, 'args');
  writeFileSync(join(root, 'viewer'), `#!/bin/sh\nprintf '%s\\n' "launch $#" "$@" >>'${args}'\n`);
  chmodSync(join(root, 'viewer'), 0o755);
  const entry = (id, name, types, extra = '') => writeFileSync(join(apps, id), `[Desktop Entry]\nType=Application\nName=${name}\n${extra}Exec=${join(root, 'viewer')} %F\nMimeType=${types}\n`);
  entry('dots-test-viewer.desktop', 'Test viewer', 'image/jpeg;', 'GenericName=Image viewer\n');
  entry('other.desktop', 'Other', 'image/jpeg;image/png;');
  entry('png-only.desktop', 'PNG only', 'image/png;');
  // Gio finds an entry's types in the folder's mimeinfo.cache, as update-desktop-database writes it, not in the entry itself.
  writeFileSync(join(apps, 'mimeinfo.cache'), '[MIME Cache]\nimage/jpeg=dots-test-viewer.desktop;other.desktop;\nimage/png=other.desktop;png-only.desktop;\n');
  const real = join(dotfiles, 'mimeapps.list');
  writeFileSync(real, MIMEAPPS);
  symlinkSync(real, join(config, 'mimeapps.list'));
  const files = { a: join(root, 'a.jpg'), b: join(root, 'b.jpg'), c: join(root, 'c.png') };
  writeFileSync(files.a, JPEG);
  writeFileSync(files.b, JPEG);
  writeFileSync(files.c, PNG);
  const env = { ...process.env, XDG_DATA_HOME: join(root, 'data'), XDG_DATA_DIRS: share, XDG_CONFIG_HOME: config, XDG_CONFIG_DIRS: join(root, 'etc') };
  delete env.XDG_CURRENT_DESKTOP;
  const run = (...a) => spawnSync(bin, a, { env, encoding: 'utf8', timeout: 10000 });
  return { root, files, env, run, real, link: join(config, 'mimeapps.list'), args };
}

test('lists the apps that declare the files\' type, the default first', (t) => {
  const s = scratch(t);
  const r = s.run('list', s.files.a, s.files.b);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), {
    type: 'image/jpeg',
    description: 'JPEG image',
    apps: [
      { id: 'other.desktop', name: 'Other', generic: null, exec: 'viewer', default: true },
      { id: 'dots-test-viewer.desktop', name: 'Test viewer', generic: 'Image viewer', exec: 'viewer', default: false },
    ],
  });
});

test('files of two types list only the apps that declare both, and no description', (t) => {
  const s = scratch(t);
  const r = s.run('list', s.files.c, s.files.a);
  assert.equal(r.status, 0, r.stderr);
  const out = JSON.parse(r.stdout);
  assert.equal(out.description, null);
  assert.deepEqual(out.apps.map((a) => a.id), ['other.desktop']);
});

test('opens every file in the app in one launch', (t) => {
  const s = scratch(t);
  const r = s.run('open', 'dots-test-viewer.desktop', s.files.a, s.files.b, s.files.c);
  assert.equal(r.status, 0, r.stderr);
  const deadline = Date.now() + 5000;
  while (!existsSync(s.args) && Date.now() < deadline) spawnSync('sleep', ['0.05']);
  assert.equal(readFileSync(s.args, 'utf8'), `launch 3\n${s.files.a}\n${s.files.b}\n${s.files.c}\n`);
});

test('a default is written into the file mimeapps.list links to, keeping the link and every other line', (t) => {
  const s = scratch(t);
  for (const type of ['image/jpeg', 'image/png']) {
    const r = s.run('default', type, 'dots-test-viewer.desktop');
    assert.equal(r.status, 0, r.stderr);
  }
  assert.ok(lstatSync(s.link).isSymbolicLink());
  assert.equal(
    readFileSync(s.real, 'utf8'),
    '[Default Applications]\ntext/plain=org.gnome.TextEditor.desktop\nimage/jpeg=dots-test-viewer.desktop\nimage/png=dots-test-viewer.desktop\n\n[Added Associations]\nimage/png=other.desktop;\n',
  );
  const q = spawnSync('xdg-mime', ['query', 'default', 'image/jpeg'], { env: s.env, encoding: 'utf8' });
  assert.equal(q.stdout.trim(), 'dots-test-viewer.desktop');
});
