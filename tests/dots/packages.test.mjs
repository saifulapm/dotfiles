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
const macOnly = ['arm-none-eabi-gcc-cs', 'libva-devel', 'binutils', 'kernel-headers'];

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

// The tools Saiful and his agents reach for (v2.2): delta and difft for diffs, gm, shellcheck, dig and docker for the agents.
test('the everyday CLI tools are declared for every arch, and eza is not', () => {
  for (const name of ['git-delta', 'difftastic', 'tree', 'yq', 'glow', 'gum', 'tokei', 'trash-cli', 'uv', 'ShellCheck', 'GraphicsMagick', 'bind-utils', 'podman-docker', 'bluez-tools']) {
    assert.equal(byName.get(name)?.arch, 'all', `${name} arch`);
    assert.match(byName.get(name).why, /\w/, `${name} why`);
  }
  assert.equal(byName.has('eza'), false);
});

// The shell, Chromium and the clipboard endpoint use these, and a minimal Fedora need not have them.
test('what the shell and Chromium call is declared, not left to the base image', () => {
  for (const name of ['upower', 'power-profiles-daemon', 'ddcutil', 'pipewire-pulseaudio', 'pandoc-cli']) {
    assert.equal(byName.get(name)?.arch, 'all', `${name} arch`);
    assert.match(byName.get(name).why, /\w/, `${name} why`);
  }
});

// Fedora's ffmpeg-free also answers to "ffmpeg", so a plain dnf install of it succeeds without RPM Fusion's build.
test('ffmpeg comes from RPM Fusion free', () => {
  assert.equal(byName.get('ffmpeg')?.rpmfusion, 'free');
});

// The NUC's Intel wifi and video decode; Fedora's libva-intel-media-driver leaves out codecs RPM Fusion's build has.
test('the NUC\'s wifi firmware, VA driver and vainfo are declared for x86_64 only', () => {
  assert.equal(byName.get('iwlwifi-mvm-firmware')?.arch, 'x86_64');
  assert.equal(byName.get('intel-media-driver')?.arch, 'x86_64');
  assert.equal(byName.get('intel-media-driver').rpmfusion, 'nonfree');
  assert.equal(byName.get('libva-utils')?.arch, 'x86_64');
  for (const name of ['iwlwifi-mvm-firmware', 'intel-media-driver', 'libva-utils']) assert.match(byName.get(name).why, /\w/, `${name} why`);
});

// Google's adb, aapt2 and NDK hosts are x86_64 only, so the Macs take adb from Fedora and build scrcpy against RPM Fusion's ffmpeg.
test('the mobile toolchain\'s packages: JDK 25, clang and lld everywhere, adb and scrcpy\'s build deps on the Macs', () => {
  for (const name of ['java-25-openjdk-devel', 'clang', 'lld']) assert.equal(byName.get(name)?.arch, 'all', `${name} arch`);
  for (const name of ['android-tools', 'SDL3-devel', 'libusb1-devel']) assert.equal(byName.get(name)?.arch, 'aarch64', `${name} arch`);
  assert.equal(byName.get('ffmpeg-devel').rpmfusion, 'free');
  for (const name of ['java-25-openjdk-devel', 'clang', 'lld', 'android-tools', 'SDL3-devel', 'libusb1-devel', 'ffmpeg-devel']) assert.match(byName.get(name).why, /\w/, `${name} why`);
});

// The add-ons picked from awesome-niri (2026-10-27): clicking from the keyboard, reading raw input events, one app over ssh.
test('wl-kbptr, wev and waypipe are declared for every arch', () => {
  for (const name of ['wl-kbptr', 'wev', 'waypipe']) {
    assert.equal(byName.get(name)?.arch, 'all', `${name} arch`);
    assert.match(byName.get(name).why, /\w/, `${name} why`);
  }
});

// Every machine is a remote and a viewer: wayvnc serves, and wlvncc builds from its pin against these on both arches.
test('wayvnc and everything wlvncc builds against are declared for every arch', () => {
  const build = [
    'meson', 'ninja-build', 'pkgconf-pkg-config', 'libdrm-devel', 'ffmpeg-devel', 'mesa-libgbm-devel',
    'libxkbcommon-devel', 'pixman-devel', 'wayland-devel', 'libglvnd-devel', 'lzo-devel', 'zlib-ng-compat-devel', 'libjpeg-turbo-devel', 'openssl-devel',
  ];
  for (const name of ['wayvnc', ...build]) {
    assert.equal(byName.get(name)?.arch, 'all', `${name} arch`);
    assert.match(byName.get(name).why, /\w/, `${name} why`);
  }
  assert.equal(byName.get('ffmpeg-devel').rpmfusion, 'free');
});
