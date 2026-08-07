#!/usr/bin/env bash
# One-time prep so browser theme colors work WITHOUT sudo afterwards: the
# enterprise-policy dirs are created and handed to the user, and from then on
# bin/theme-apply writes color.json ({BrowserThemeColor, BrowserColorScheme})
# on every theme change and pokes running browsers with
# --refresh-platform-policy. Port of the Arch install.sh mechanism (omarchy's
# omarchy-theme-set-browser); chown to the user rather than Arch's
# chmod a+rw — same effect for theme-apply, not world-writable.
#
# The same dirs also get the repo's static policy
# (chromium/policies/extensions.json): ExtensionInstallForcelist with uBlock
# Origin Lite, so a fresh machine's browser installs it from the Web Store on
# first launch and keeps it auto-updated. Lite, not classic uBlock Origin:
# classic is Manifest V2, which Chromium 139+ cannot load at all.
#
# Same root policy as 00-install-packages: sudo can only prompt from a
# terminal, background applies skip loudly and the next terminal apply lands
# it.
set -uo pipefail

prep() {
  local dir="$1"
  [ -w "$dir" ] && return 0
  sudo mkdir -p "$dir" && sudo chown "${USER:-$(id -un)}" "$dir"
}

# Only dirs for browsers actually present on this machine.
targets=()
command -v chromium-browser >/dev/null 2>&1 && targets+=("/etc/chromium/policies/managed")
command -v google-chrome >/dev/null 2>&1 && targets+=("/etc/opt/chrome/policies/managed")
[ ${#targets[@]} -eq 0 ] && exit 0

need=0
for dir in "${targets[@]}"; do [ -w "$dir" ] || need=1; done

if [ "$need" -ne 0 ]; then
  if ! sudo -v 2>/dev/null; then
    echo "chromium-policy: sudo unavailable — browser theme color + extension policy stay off (rerun 'chezmoi apply' in a terminal)" >&2
    exit 0
  fi

  for dir in "${targets[@]}"; do
    prep "$dir" || echo "chromium-policy: could not prep $dir" >&2
  done

  # Land the current theme's color immediately rather than waiting for the
  # next theme change.
  "$HOME/.dotfiles/bin/theme-apply" >/dev/null 2>&1 || true
fi

# Sync the static extension policy on every apply (cheap: byte-compare
# first). A dir that is still root-owned — sudo declined above — is skipped
# and the next terminal apply lands it.
src="$HOME/.dotfiles/chromium/policies/extensions.json"
for dir in "${targets[@]}"; do
  [ -w "$dir" ] || continue
  cmp -s "$src" "$dir/extensions.json" || cp "$src" "$dir/extensions.json"
done

exit 0
