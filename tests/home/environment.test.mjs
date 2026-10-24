// environment.d gives the systemd user manager Electron's Wayland hint, Chromium's flags, the ssh-agent socket and the Android SDK.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, mkdirSync, copyFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const repo = new URL('../../', import.meta.url).pathname;
const dir = join(repo, 'home/dot_config/environment.d');
const read = (f) => readFileSync(join(dir, f), 'utf8');
const generator = '/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator';

test('chromium gets v1\'s flags, no new-tab footer, and the rendered theme and new-tab extensions on one CHROMIUM_USER_FLAGS line, without the v1 extension', () => {
  const lines = read('60-chromium.conf').split('\n').filter((l) => l.startsWith('CHROMIUM_USER_FLAGS='));
  assert.equal(lines.length, 1);
  assert.equal(
    lines[0],
    'CHROMIUM_USER_FLAGS=--ozone-platform-hint=auto --force-color-profile=srgb --no-default-browser-check --enable-features=TouchpadOverscrollHistoryNavigation,WaylandPerSurfaceScale,WaylandUiScale,OverlayScrollbar --disable-features=AimEnabled,AiMode,AiModeOmniboxEntryPoint,AiModePageActionIconView,AiModeEntryPointAlwaysNavigates,AiModeStartPack,AimEligibilityService,AimUrlNavigation,AimUrlInterceptPassthrough,Compose,LensOverlay,OptimizationGuideOnDeviceModel,OptimizationGuideModelDownloading,WallpaperSearch,NtpFooter --load-extension=${HOME}/.local/state/dots/theme-out/chromium-theme,${HOME}/.local/state/dots/theme-out/chromium-newtab',
  );
  assert.doesNotMatch(read('60-chromium.conf'), /\.dotfiles/);
});

test('Electron apps draw on Wayland', () => {
  assert.match(read('40-wayland.conf'), /^ELECTRON_OZONE_PLATFORM_HINT=wayland$/m);
});

test('SSH_AUTH_SOCK points at the user ssh-agent socket', () => {
  assert.match(read('65-ssh-agent.conf'), /^SSH_AUTH_SOCK=\$\{XDG_RUNTIME_DIR\}\/ssh-agent\.socket$/m);
});

test('ssh-agent.socket is enabled at login from the packaged unit', () => {
  assert.equal(readFileSync(join(repo, 'home/dot_config/systemd/user/sockets.target.wants/symlink_ssh-agent.socket'), 'utf8').trim(), '/usr/lib/systemd/user/ssh-agent.socket');
});

test('the environment.d generator expands every file', { skip: !existsSync(generator) }, () => {
  const home = mkdtempSync(join(tmpdir(), 'envd-'));
  mkdirSync(join(home, 'environment.d'));
  for (const f of ['40-wayland.conf', '60-chromium.conf', '65-ssh-agent.conf', '70-android.conf']) copyFileSync(join(dir, f), join(home, 'environment.d', f));
  const out = execFileSync(generator, { env: { XDG_CONFIG_HOME: home, XDG_RUNTIME_DIR: '/run/user/1000', HOME: home, PATH: '/usr/bin' }, encoding: 'utf8' });
  assert.match(out, /^ELECTRON_OZONE_PLATFORM_HINT=wayland$/m);
  assert.match(out, /^SSH_AUTH_SOCK=\/run\/user\/1000\/ssh-agent\.socket$/m);
  assert.match(out, new RegExp(`^ANDROID_HOME=${home}/Android/Sdk$`, 'm'));
  assert.match(out, new RegExp(`^PATH=${home}/\\.cargo/bin:/usr/bin:${home}/\\.local/bin:${home}/Android/Sdk/platform-tools:${home}/Android/Sdk/cmdline-tools/latest/bin:${home}/Android/Sdk/emulator$`, 'm'));
  assert.match(out, /^CHROMIUM_USER_FLAGS=.*--force-color-profile=srgb.*AimEnabled/m);
  assert.match(out, new RegExp(`^CHROMIUM_USER_FLAGS=.* --load-extension=${home}/\\.local/state/dots/theme-out/chromium-theme,${home}/\\.local/state/dots/theme-out/chromium-newtab"?$`, 'm'));
});
