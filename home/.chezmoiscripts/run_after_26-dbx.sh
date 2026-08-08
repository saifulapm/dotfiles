#!/usr/bin/env bash
# dbx — GUI database client for 70+ engines (MySQL, Postgres, SQLite, ...),
# github.com/t8y2/dbx. User pick 2026-08-08 off the new-tooling sweep; it is
# the GUI half of this box's database story, sitting next to usql (the CLI half,
# installed by run_after_10) and the socket-activated podman containers in
# run_after_16-dev-services.
#
# Why an RPM and not the ~/.local/bin tarball every other prebuilt tool uses:
# dbx is a Tauri app, so it is a real desktop window, not a binary. The RPM is
# what carries /usr/share/applications/DBX.desktop and the hicolor icons, which
# is what puts it in the launcher — the whole point of taking the GUI over the
# browser-static build (the alternative, explicitly weighed and declined
# 2026-08-08: it would have cost 0 new packages but would have been one more
# thing served over HTTP, and the user wanted the native window).
#
# The cost, recorded honestly because it is the largest single dependency this
# repo pulls for one app: the RPM needs libwebkit2gtk-4.1, libappindicator3 and
# libgtk-3. Only libgtk-3 was already present; webkit2gtk4.1 +
# libappindicator-gtk3 + 6 transitive packages are 35 MiB down / 124 MiB
# installed (measured 2026-08-08). They are deliberately NOT declared as [[pkg]]
# entries in the manifest: dnf resolves them from the RPM's own Requires, which
# keeps them marked as dependencies rather than user-installed, so removing dbx
# lets `dnf autoremove` take the browser engine with it. Declaring them would
# strand 124 MiB on the disk forever.
#
# Same root policy as 00-install-packages and 14-chromium-policy: sudo can only
# prompt from a terminal, background applies skip loudly and the next terminal
# apply lands it.
set -uo pipefail

warn() { echo "dbx: $*" >&2; }

# Guarded on the rpm, not `command -v dbx`: the binary lands in /usr/bin, so a
# stale hand-built copy on PATH must not silently satisfy this.
rpm -q dbx >/dev/null 2>&1 && exit 0

arch="$(uname -m)"   # aarch64 | x86_64 — dbx names its RPMs the same way

if ! sudo -v 2>/dev/null; then
  warn "sudo unavailable — skipping (rerun 'chezmoi apply' in a terminal)"
  exit 0
fi

url="$(curl -fsSL "https://api.github.com/repos/t8y2/dbx/releases/latest" 2>/dev/null \
  | jq -r --arg re "^DBX-.*\\.${arch}\\.rpm$" \
      '.assets[] | select(.name | test($re)) | .browser_download_url' \
  | head -1)"

[ -z "$url" ] && { warn "no ${arch} rpm in the latest release"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL -o "$tmp/dbx.rpm" "$url"; then
  warn "download failed"
  exit 0
fi

# install_weak_deps=False matches the policy 00-install-packages enforces in
# /etc/dnf/dnf.conf; passed explicitly so this works even on a machine where
# that script has not run yet.
if sudo dnf install --setopt=install_weak_deps=False -y "$tmp/dbx.rpm"; then
  echo "dbx: installed"
else
  warn "dnf install failed"
fi

exit 0
