// environment.d gives the systemd user manager Chromium's flags and the ssh-agent socket.
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

test('chromium gets v1\'s flags on one CHROMIUM_USER_FLAGS line, without the v1 extension', () => {
  const lines = read('60-chromium.conf').split('\n').filter((l) => l.startsWith('CHROMIUM_USER_FLAGS='));
  assert.equal(lines.length, 1);
  assert.equal(
    lines[0],
    'CHROMIUM_USER_FLAGS=--ozone-platform-hint=auto --force-color-profile=srgb --no-default-browser-check --enable-features=TouchpadOverscrollHistoryNavigation,WaylandPerSurfaceScale,WaylandUiScale,OverlayScrollbar --disable-features=AimEnabled,AiMode,AiModeOmniboxEntryPoint,AiModePageActionIconView,AiModeEntryPointAlwaysNavigates,AiModeStartPack,AimEligibilityService,AimUrlNavigation,AimUrlInterceptPassthrough,Compose,LensOverlay,OptimizationGuideOnDeviceModel,OptimizationGuideModelDownloading,WallpaperSearch',
  );
  assert.doesNotMatch(read('60-chromium.conf'), /\.dotfiles|load-extension/);
});

test('SSH_AUTH_SOCK points at the user ssh-agent socket', () => {
  assert.match(read('65-ssh-agent.conf'), /^SSH_AUTH_SOCK=\$\{XDG_RUNTIME_DIR\}\/ssh-agent\.socket$/m);
});

test('the environment.d generator expands both files', { skip: !existsSync(generator) }, () => {
  const home = mkdtempSync(join(tmpdir(), 'envd-'));
  mkdirSync(join(home, 'environment.d'));
  for (const f of ['60-chromium.conf', '65-ssh-agent.conf']) copyFileSync(join(dir, f), join(home, 'environment.d', f));
  const out = execFileSync(generator, { env: { XDG_CONFIG_HOME: home, XDG_RUNTIME_DIR: '/run/user/1000', HOME: home, PATH: '/usr/bin' }, encoding: 'utf8' });
  assert.match(out, /^SSH_AUTH_SOCK=\/run\/user\/1000\/ssh-agent\.socket$/m);
  assert.match(out, /^CHROMIUM_USER_FLAGS=.*--force-color-profile=srgb.*AimEnabled/m);
});
