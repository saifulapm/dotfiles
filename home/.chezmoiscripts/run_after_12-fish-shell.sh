#!/usr/bin/env bash
# Makes fish the login shell (user decision 2026-08-07). Same root policy as
# 00-install-packages: usermod needs root, sudo can only prompt from a
# terminal, so background applies skip loudly instead of hanging, and the
# next terminal apply lands it.
set -uo pipefail

target="/usr/bin/fish"

[ -x "$target" ] || { echo "fish-shell: $target missing (00-install-packages pending?) — skipping" >&2; exit 0; }

user="${USER:-$(id -un)}"
current="$(getent passwd "$user" | cut -d: -f7)"
[ "$current" = "$target" ] && exit 0

if ! sudo -v 2>/dev/null; then
  echo "fish-shell: sudo unavailable — login shell still $current (rerun 'chezmoi apply' in a terminal)" >&2
  exit 0
fi

if sudo usermod --shell "$target" "$user"; then
  echo "fish-shell: login shell set to fish (takes effect on next login)"
else
  echo "fish-shell: usermod failed" >&2
fi

exit 0
