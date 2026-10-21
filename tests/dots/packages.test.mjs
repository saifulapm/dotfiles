// packages.toml, read the way the packages script's awk reads it: one [[package]] block per entry.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const toml = readFileSync(new URL('../../packages.toml', import.meta.url), 'utf8');
const entries = toml
  .split(/^\[\[package\]\]$/m)
  .slice(1)
  .map((block) => Object.fromEntries([...block.matchAll(/^(\w+) *= *"([^"]*)"$/gm)].map((m) => [m[1], m[2]])));
const byName = new Map(entries.map((e) => [e.name, e]));

const everyArch = [
  'chromium', 'tailscale', 'pipewire', 'wireplumber', 'brightnessctl', 'wf-recorder', 'grim', 'slurp', 'wlrctl',
  'ydotool', 'tesseract', 'tesseract-langpack-eng', 'tesseract-langpack-ben', 'zbar', 'python3-gobject', 'just',
  'mpv', 'imv', 'zathura', 'zathura-pdf-mupdf', 'yt-dlp', 'pass-otp', 'ffmpeg', 'ruby', 'rubypick', 'golang',
  'gtk4', 'libadwaita', 'lynx', 'php-cli', 'php-fpm', 'php-mbstring', 'php-xml', 'php-pdo', 'php-intl', 'php-process', 'php-mysqlnd', 'php-pgsql', 'php-gd', 'php-bcmath', 'php-pecl-redis6', 'composer', 'caddy', 'podman',
];
const macOnly = ['meson', 'ninja-build', 'arm-none-eabi-gcc-cs', 'libva-devel', 'binutils', 'pkgconf-pkg-config', 'libdrm-devel', 'kernel-headers'];

test('every daily package is declared for every arch with a reason', () => {
  for (const name of everyArch) {
    assert.equal(byName.get(name)?.arch, 'all', `${name} arch`);
    assert.match(byName.get(name).why, /\w/, `${name} why`);
  }
});

test('the AVD firmware and VA driver build tools are declared for the Macs only', () => {
  for (const name of macOnly) {
    assert.equal(byName.get(name)?.arch, 'aarch64', `${name} arch`);
    assert.match(byName.get(name).why, /\w/, `${name} why`);
  }
});

// Fedora's ffmpeg-free also answers to "ffmpeg", so a plain dnf install of it succeeds without RPM Fusion's build.
test('ffmpeg comes from RPM Fusion free', () => {
  assert.equal(byName.get('ffmpeg')?.rpmfusion, 'free');
});
