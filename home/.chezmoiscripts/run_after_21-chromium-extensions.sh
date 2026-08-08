#!/usr/bin/env bash
# Register the native messaging hosts for the Chromium extensions (omarchy's
# copy-url + yt-dlp, CREDITS.md; browserpass). The omarchy extensions load
# straight from the repo via --load-extension in CHROMIUM_USER_FLAGS
# (environment.d/60-chromium.conf); this half tells Chromium which script a
# `sendNativeMessage` may launch. User-level files only — no sudo. The host
# names keep omarchy's com.omarchy.* ids because the extension code (direct
# copies) calls them by that exact string, and their manifests pin the
# extension IDs with a `key`, so the allowed_origins match from any path.
#
# browserpass is the odd one out and deliberately so: the extension is NOT
# repo-bundled (it installs from the Chrome Web Store, which is also what
# keeps it auto-updating — 3.12.0 as of 2026-05), and its host binary is
# Fedora's /usr/bin/browserpass-native rather than a script in bin/. Fedora's
# `browserpass` package ships ONLY that binary — no host manifest, no setup
# script, unlike upstream's `make hosts-chromium` — so without the json this
# script writes, the extension finds no native component and every lookup
# fails with "host not found". Its three allowed_origins are upstream's
# verbatim (browser-files/chromium-host.json): the Web Store id plus two
# development ids. Getting one character wrong here fails silently, so they
# are copied, never retyped.
#
# The -x guard is why this loop can carry a packaged binary at all: a host
# whose target is missing (browserpass declared in the manifest but not yet
# installed — any background apply, which cannot sudo) would otherwise get a
# json pointing at nothing, and Chromium reports that as a confusing native
# error rather than an absent feature. Skipped now, registered on the next
# terminal apply.
#
# Warn-don't-abort like every neighbour (audit 2026-08-08): this script sat
# on set -e with nothing to justify it, so an unwritable json here would have
# silently skipped 22-26 and 99 — the memory setup, both model downloads, the
# daemon trim and the first-boot theme.
set -uo pipefail

src="${CHEZMOI_WORKING_TREE:-$HOME/.dotfiles}"
dest="$HOME/.config/chromium/NativeMessagingHosts"

declare -A hosts=(
  [com.omarchy.copy_url]="$src/bin/chromium-copy-url-host"
  [com.omarchy.ytdlp]="$src/bin/chromium-ytdlp-host"
  [com.github.browserpass.native]="/usr/bin/browserpass-native"
)

mkdir -p "$dest" \
  || { echo "chromium-extensions: cannot create $dest — skipped" >&2; exit 0; }
registered=()
for name in "${!hosts[@]}"; do
  template="$src/chromium/native-messaging-hosts/$name.json"
  [ -f "$template" ] || { echo "chromium-extensions: missing $template, skipped" >&2; continue; }
  [ -x "${hosts[$name]}" ] \
    || { echo "chromium-extensions: ${hosts[$name]} not executable, $name skipped" >&2; continue; }
  if sed "s|__HOST_PATH__|${hosts[$name]}|g" "$template" >"$dest/$name.json"; then
    registered+=("$name")
  else
    echo "chromium-extensions: writing $name.json failed" >&2
  fi
done
echo "chromium-extensions: native messaging hosts registered (${registered[*]:-none})"
