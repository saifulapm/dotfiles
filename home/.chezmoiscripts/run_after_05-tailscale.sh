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
# Serve config is keyed by the node's DNS NAME at publish time — after a
# rename in the admin console the stored mapping still says the old name
# and every request under the new one gets tailscaled's own "404 page not
# found" (found live 2026-08-11: the fedora→macbook/nuc renames silently
# killed machine-to-machine sync). So the guard checks for the CURRENT
# name, not just the port, and re-keys via reset when they disagree.
# NOTE: `serve reset` wipes EVERY mapping, not only this one. Until
# 2026-08-19 this comment said the clipboard proxy was the only serve
# user on these machines; hub (:8787) is a second one now, so the block
# below re-publishes it after any reset.
if [ "$state" = "Running" ]; then
  dnsname="$(tailscale status --json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))' 2>/dev/null || true)"
  serve_now="$(tailscale serve status 2>/dev/null || true)"
  serve_ok=""
  case $serve_now in
  *127.0.0.1:9411*)
    case $serve_now in
    *"$dnsname"*) [ -n "$dnsname" ] && serve_ok=1 ;;
    esac
    ;;
  esac
  if [ -z "$serve_ok" ]; then
    case $serve_now in
    *127.0.0.1:9411*) tailscale serve reset >/dev/null 2>&1 || true ;;
    esac
    if tailscale serve --bg --http=80 9411 >/dev/null 2>&1; then
      echo "tailscale: clipboard endpoint published (http://$dnsname → 127.0.0.1:9411)"
    else
      echo "tailscale: clipboard endpoint NOT published — run: tailscale serve --bg --http=80 9411" >&2
    fi
  fi
fi

# hub (~/Sites/github/workflow, specs/hub-v1.md §7) publishes loopback :8787 to
# the tailnet the same way, added 2026-08-19. It needs its own block for two
# reasons: the `serve reset` above wipes every mapping, so a machine rename plus
# `chezmoi apply` would otherwise silently drop hub off the tailnet; and the
# rename re-keys hub's mapping exactly as it re-keys the clipboard's. Guarded on
# the unit file, because this script does not decide that hub should run — it
# only refuses to be the thing that takes it off the tailnet. `--bg` is a no-op
# when the mapping is already right, so this acts once per machine.
if [ "$state" = "Running" ] && [ -f "$HOME/.config/systemd/user/hub.service" ]; then
  serve_now="$(tailscale serve status 2>/dev/null || true)"
  hub_ok=""
  case $serve_now in
  *127.0.0.1:8787*)
    case $serve_now in
    *"$dnsname"*) [ -n "$dnsname" ] && hub_ok=1 ;;
    esac
    ;;
  esac
  if [ -z "$hub_ok" ]; then
    if tailscale serve --bg --http=8787 8787 >/dev/null 2>&1; then
      echo "tailscale: hub endpoint published (http://$dnsname:8787 → 127.0.0.1:8787)"
    else
      echo "tailscale: hub endpoint NOT published — run: tailscale serve --bg --http=8787 8787" >&2
    fi
  fi
fi

# Clipboard VIP route: every machine advertises 10.99.99.99/32 and the
# control plane keeps the route pointed at an online one (HA subnet-router
# failover — no tags, unlike Tailscale Services, whose tagged-host
# requirement would break Taildrop per kb/1106). The phone's shortcuts
# target http://10.99.99.99:9411/ and stop caring which machine is awake.
# `tailscale set --advertise-routes` REPLACES the whole set, so the current
# routes are merged in; the operator may set prefs, no root needed. The
# route stays "pending" until approved once per machine in the admin
# console (Machines → the machine → Edit route settings) — nothing breaks
# while it waits. The local halves (VIP on lo, firewall) are run_after_20's.
if [ "$state" = "Running" ]; then
  vip_route="10.99.99.99/32"
  current_routes="$(tailscale debug prefs 2>/dev/null \
    | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin).get("AdvertiseRoutes") or []))' 2>/dev/null || true)"
  case ",$current_routes," in
  *",$vip_route,"*) ;;
  *)
    merged="$vip_route"
    [ -n "$current_routes" ] && merged="$current_routes,$vip_route"
    if tailscale set --advertise-routes="$merged" 2>/dev/null; then
      echo "tailscale: clipboard VIP route advertised ($vip_route) — approve it once in the admin console (Machines → this machine → Edit route settings)"
    else
      echo "tailscale: clipboard VIP route NOT advertised — run: tailscale set --advertise-routes=$merged" >&2
    fi
    ;;
  esac
fi

exit 0
