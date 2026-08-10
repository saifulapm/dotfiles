#!/usr/bin/env bash
# Tailscale bring-up: enable the system daemon and set the operator so the
# bar widget's write verbs (toggle, exit nodes, Taildrop) work without root.
# What CANNOT be scripted is the login itself — `tailscale up` opens an
# interactive browser auth — so that step is surfaced loudly instead of
# pretended away. The bar's tailscale panel also carries the same login flow.
set -uo pipefail

command -v tailscale >/dev/null 2>&1 || exit 0

# Same root ladder as 01-autologin / 03-portal-backend: cached sudo →
# interactive sudo (the fresh-machine TTY path) → pkexec on-screen dialog
# (the background-run path).
run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "tailscale: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

if ! systemctl is-active tailscaled.service >/dev/null 2>&1; then
  if run_root /usr/bin/systemctl enable --now tailscaled.service; then
    echo "tailscale: tailscaled enabled"
  else
    echo "tailscale: could not enable tailscaled (no root route) — rerun 'chezmoi apply' in a terminal" >&2
    exit 0
  fi
fi

# Operator: `switch --list` is the cheapest verb that fails without it. Set
# BEFORE the login check so the login itself needs no sudo afterwards.
if ! tailscale switch --list >/dev/null 2>&1; then
  if run_root /usr/bin/tailscale set --operator="$USER"; then
    echo "tailscale: operator set to $USER"
  else
    echo "tailscale: operator not set — the bar widget stays read-only until: sudo tailscale set --operator=$USER" >&2
  fi
fi

state="$(tailscale status --json 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState",""))' 2>/dev/null || true)"
if [ "$state" != "Running" ]; then
  echo "tailscale: NOT logged in (state: ${state:-unknown}). One interactive step remains:" >&2
  echo "    tailscale up          # prints a login URL (no sudo needed once the operator is set)" >&2
  echo "  or click the bar's tailscale widget and use its login row." >&2
  command -v notify-send >/dev/null 2>&1 \
    && notify-send -a qshell "Tailscale needs login" "Run: tailscale up — or use the bar widget's login row" 2>/dev/null || true
fi

# Clipboard endpoint (bin/clipboard-serve): publish loopback :9411 to the
# tailnet as plain HTTP on :80 — tailscaled terminates it inside the tunnel,
# so only tailnet devices can ever reach it and no real port opens. Plain
# HTTP is deliberate: this tailnet has no cert domains enabled, and the path
# is WireGuard-encrypted regardless. `--bg` writes the mapping into
# tailscaled's profile where it survives reboots, so this acts once per
# machine and is a no-op after. Captured into a variable, not piped to grep
# (the pipefail+grep -q SIGPIPE class).
if [ "$state" = "Running" ]; then
  serve_now="$(tailscale serve status 2>/dev/null || true)"
  case $serve_now in
  *127.0.0.1:9411*) ;;
  *)
    if tailscale serve --bg --http=80 9411 >/dev/null 2>&1; then
      echo "tailscale: clipboard endpoint published (tailnet :80 → 127.0.0.1:9411)"
    else
      echo "tailscale: clipboard endpoint NOT published — run: tailscale serve --bg --http=80 9411" >&2
    fi
    ;;
  esac
fi

exit 0
