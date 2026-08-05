#!/usr/bin/env bash
# Dropbox, headless, NUC only (user decision 2026-08-06). Dropbox ships no
# aarch64 Linux daemon at all, so this script is a no-op on the Macs — the
# bar's dropbox widget stays hidden there (it is presence-gated on the CLI).
#
# Deliberately NOT nautilus-dropbox: that rpm needs the RPM Fusion nonfree
# repo and hard-requires nautilus (a GNOME chain this desktop does not
# carry), all to obtain three files. Dropbox's own headless route is the
# same daemon with none of that: the proprietary dropboxd tarball into
# ~/.dropbox-dist and their python3 dropbox.py CLI as ~/.local/bin/dropbox —
# which is one of the two names bin/dropbox-status probes (the other,
# dropbox-cli, is Arch's).
#
# Failures warn instead of aborting, like the other user-tool scripts: a
# flaky network must not stop the rest of an apply.
set -uo pipefail

[ "$(uname -m)" = "x86_64" ] || exit 0

warn() { echo "dropbox: $*" >&2; }

# The daemon. The tarball unpacks to ~/.dropbox-dist/dropboxd and friends.
if [ ! -x "$HOME/.dropbox-dist/dropboxd" ]; then
  if curl -fsSL "https://www.dropbox.com/download?plat=lnx.x86_64" | tar -xzf - -C "$HOME"; then
    echo "dropbox: daemon installed to ~/.dropbox-dist"
  else
    warn "daemon download failed (offline?) — rerun 'chezmoi apply'"
  fi
fi

# The CLI (their official python3 control script), under the name the shell's
# status helper probes.
if ! command -v dropbox >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/dropbox" ]; then
  mkdir -p "$HOME/.local/bin"
  if curl -fsSL "https://www.dropbox.com/download?dl=packages/dropbox.py" -o "$HOME/.local/bin/dropbox"; then
    chmod +x "$HOME/.local/bin/dropbox"
    echo "dropbox: CLI installed as ~/.local/bin/dropbox"
  else
    warn "CLI download failed"
  fi
fi

# Keep the daemon alive across logins. Written here, not chezmoi-managed:
# a managed unit would exist on the Macs too, where enabling it can only
# fail (same reasoning as the voxtype unit).
unit="$HOME/.config/systemd/user/dropbox.service"
if [ -x "$HOME/.dropbox-dist/dropboxd" ]; then
  if [ ! -f "$unit" ]; then
    mkdir -p "$(dirname "$unit")"
    cat >"$unit" <<'EOF'
[Unit]
Description=Dropbox daemon (headless, ~/.dropbox-dist)

[Service]
ExecStart=%h/.dropbox-dist/dropboxd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    echo "dropbox: user unit written"
  fi
  state="$(systemctl --user is-system-running 2>/dev/null || true)"
  if [ "$state" = "running" ] || [ "$state" = "degraded" ]; then
    systemctl --user daemon-reload
    systemctl --user is-enabled dropbox.service >/dev/null 2>&1 \
      || systemctl --user enable --now dropbox.service 2>/dev/null \
      || warn "could not enable dropbox.service"
  fi
fi

# The link is interactive: the first daemon run prints an authentication URL.
# The bar widget's login row walks the same path; say it loudly here too.
# (Captured output + bash matching, not `status | grep -q` — under pipefail
# grep -q SIGPIPEs the producer and fails the pipeline intermittently.)
if command -v dropbox >/dev/null 2>&1 || [ -x "$HOME/.local/bin/dropbox" ]; then
  dbx="$(command -v dropbox || echo "$HOME/.local/bin/dropbox")"
  status_out="$("$dbx" status 2>/dev/null || true)"
  if [ -z "$status_out" ] || [[ $status_out == *"isn't running"* ]] || [[ ${status_out,,} == *link* ]]; then
    echo "dropbox: NOT linked yet. One interactive step remains:" >&2
    echo "    dropbox start   # prints a login URL — or use the bar widget's login row" >&2
  fi
fi

exit 0
