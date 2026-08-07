#!/usr/bin/env bash
# Register the native messaging hosts for the bundled Chromium extensions
# (omarchy's copy-url + yt-dlp, CREDITS.md). The extensions themselves load
# straight from the repo via --load-extension in CHROMIUM_USER_FLAGS
# (environment.d/60-chromium.conf); this half tells Chromium which script a
# `sendNativeMessage` may launch. User-level files only — no sudo. The host
# names keep omarchy's com.omarchy.* ids because the extension code (direct
# copies) calls them by that exact string, and their manifests pin the
# extension IDs with a `key`, so the allowed_origins match from any path.
set -euo pipefail

src="${CHEZMOI_WORKING_TREE:-$HOME/.dotfiles}"
dest="$HOME/.config/chromium/NativeMessagingHosts"

declare -A hosts=(
  [com.omarchy.copy_url]="$src/bin/chromium-copy-url-host"
  [com.omarchy.ytdlp]="$src/bin/chromium-ytdlp-host"
)

mkdir -p "$dest"
for name in "${!hosts[@]}"; do
  template="$src/chromium/native-messaging-hosts/$name.json"
  [ -f "$template" ] || { echo "chromium-extensions: missing $template, skipped" >&2; continue; }
  sed "s|__HOST_PATH__|${hosts[$name]}|g" "$template" >"$dest/$name.json"
done
echo "chromium-extensions: native messaging hosts registered (${!hosts[*]})"
