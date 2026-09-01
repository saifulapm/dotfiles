#!/usr/bin/env bash
# Herd-style https://<project>.test (decision 2026-08-07). Three moving parts,
# and only the first of them is ever running:
#
#   1. dnsmasq answers *.test with 127.0.0.1 on 127.0.0.2:53 (moved off
#      127.0.0.1 on 2026-09-02 for the uBlockDNS client — see
#      run_after_18-ublockdns.sh), and a systemd-resolved drop-in routes the
#      `test` domain there. This is the one always-on piece — ~2 MB, and DNS
#      cannot be socket-activated on demand because resolved needs an answer
#      before anything connects.
#   2. caddy serves the sites over https with its own CA, as a USER service
#      on 38080/38443, woken by sockets holding 80/443 (see
#      ~/.config/systemd/user/caddy-dev*). Idle 10 min → gone.
#   3. php-fpm 8.4 (and 8.3, for pinned projects) behind the same socket
#      pattern on 9084/9083. Idle → gone.
#
# So this script's job is the parts the user session cannot do for itself:
# three files under /etc, and lighting the user sockets.
#
# Same root policy as 14-chromium-policy and 01-autologin — cached sudo, then
# interactive sudo, then pkexec's on-screen dialog — so a background apply can
# still land it with one visible approval. Warn-don't-abort throughout: a
# machine that has not installed caddy/dnsmasq yet gets a loud skip and the
# next `chezmoi apply` (after 00-install-packages runs) finishes the job.
set -uo pipefail
warn() { echo "test-domains: $*" >&2; }

# Empty directories chezmoi cannot represent (see 15-user-dirs for why a
# .keep would become a stray symlink in symlink mode). The fpm log directory
# must exist as a REAL directory before the units first run — see the comment
# in php84-fpm.service about systemd symlinking it onto ~/.config/php-fpm.
mkdir -p "$HOME/.config/caddy/sites" "$HOME/.local/state/php-fpm"

run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "test-domains: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

# ------------------------------------------------------------------ staging
# Everything is written as the user first, then installed by ONE root call —
# the pkexec route prompts once per invocation, so a dozen small calls would
# be a dozen dialogs.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# DNS-helper parameterization (see run_after_18-ublockdns.sh), two
# independent one-line markers in ~/.config/dns-helper/:
#   profile — machine runs the uBlockDNS client; dnsmasq gains the
#             127.0.0.1 upstream (the self-filter chain).
#   serve   — an INTERFACE name (enp86s0, wld0); dnsmasq also serves that
#             interface's current address. By-interface, not a pinned IP:
#             a changed DHCP reservation heals itself (2026-09-03 request).
# Everyone else keeps the pure *.test stub.
serve_iface=""
if [ -f "$HOME/.config/dns-helper/serve" ]; then
  serve_iface=$(head -1 "$HOME/.config/dns-helper/serve" | tr -cd 'a-z0-9')
fi
has_profile=""
[ -s "$HOME/.config/dns-helper/profile" ] && has_profile=yes

cat >"$tmp/dnsmasq.conf" <<'EOF'
# *.test → this machine, for the Herd-style dev domains (managed by chezmoi,
# see run_after_17-test-domains.sh — the listen/server tail is generated
# there, from ~/.config/dns-helper/lan-ip on DNS-helper machines).
#
# Port 53 — NOT 5353 (fixed 2026-08-08): SELinux confines the systemd-started
# daemon as dnsmasq_t, which may name_bind dns_port_t (53) but not 5353.
#
# On 127.0.0.2 since 2026-09-02: the uBlockDNS client hardcodes 127.0.0.1:53
# (run_after_18). Helper machines additionally serve their LAN interface's
# CURRENT address (interface= + except-interface=lo): bare interface=
# implicitly adds loopback too and stole the client's port (hit
# 2026-09-02); except-interface=lo removes exactly that while
# listen-address keeps 127.0.0.2. bind-dynamic (not bind-interfaces): the
# interface has no address at boot, and bind-interfaces would fail the
# unit; bind-dynamic follows addresses as they come, go, and change.
address=/test/127.0.0.1
bind-dynamic
port=53
no-resolv
no-hosts
listen-address=127.0.0.2
EOF
if [ -n "$serve_iface" ]; then
  printf 'interface=%s\nexcept-interface=lo\n' "$serve_iface" >>"$tmp/dnsmasq.conf"
fi
if [ -n "$has_profile" ]; then
  printf '# The one upstream: the uBlockDNS client.\nserver=127.0.0.1\n' >>"$tmp/dnsmasq.conf"
fi

cat >"$tmp/resolved.conf" <<'EOF'
# Route the `test` domain to the dnsmasq stub (managed by chezmoi, see
# run_after_17-test-domains.sh). The ~ prefix makes this a ROUTING-only
# domain: it sends *.test lookups to dnsmasq without making it a search
# suffix or the default resolver for anything else.
# 127.0.0.2 since 2026-09-02: dnsmasq moved off 127.0.0.1 so the uBlockDNS
# client could take 127.0.0.1:53 (see run_after_18-ublockdns.sh).
[Resolve]
DNS=127.0.0.2
Domains=~test
EOF

cat >"$tmp/sysctl.conf" <<'EOF'
# Let unprivileged processes bind ports 80 and above (managed by chezmoi, see
# run_after_17-test-domains.sh). Needed because caddy-dev-http.socket and
# caddy-dev-https.socket are USER units — the whole point of the design is
# that the web server never runs as root — and 80/443 are otherwise reserved
# to uid 0. Lowers the privileged floor from 1024 to 80 for everything, which
# on a single-user dev laptop buys a lot for very little.
net.ipv4.ip_unprivileged_port_start = 80
EOF

chmod 0644 "$tmp"/*.conf

# ------------------------------------------------------------------ /etc
root_sh=""
add() { root_sh="${root_sh}${1}"$'\n'; }
stale() { ! cmp -s "$1" "$2"; }

if command -v dnsmasq >/dev/null 2>&1; then
  # is-active in the gate (audit 2026-08-08): with only cmp+is-enabled, a
  # dnsmasq that enabled but FAILED to start (the SELinux port denial lived
  # exactly here) passed every later gate and was never retried — resolved
  # kept pointing at a dead 127.0.0.1 and *.test SERVFAILed forever.
  if stale "$tmp/dnsmasq.conf" /etc/dnsmasq.d/test-domains.conf \
    || stale "$tmp/resolved.conf" /etc/systemd/resolved.conf.d/test-domains.conf \
    || ! systemctl is-enabled --quiet dnsmasq 2>/dev/null \
    || ! systemctl is-active --quiet dnsmasq 2>/dev/null; then
    add "install -D -m 0644 '$tmp/dnsmasq.conf' /etc/dnsmasq.d/test-domains.conf"
    add "install -D -m 0644 '$tmp/resolved.conf' /etc/systemd/resolved.conf.d/test-domains.conf"
    add "systemctl enable dnsmasq && systemctl restart dnsmasq"
    add "systemctl restart systemd-resolved"
  fi
else
  warn "dnsmasq not installed — *.test will not resolve yet (run 'chezmoi apply' in a terminal so 00-install-packages can install it)"
fi

if stale "$tmp/sysctl.conf" /etc/sysctl.d/99-dev-unprivileged-ports.conf; then
  add "install -D -m 0644 '$tmp/sysctl.conf' /etc/sysctl.d/99-dev-unprivileged-ports.conf"
  add "sysctl --system >/dev/null"
fi

# caddy's local CA, into the system trust store so browsers show a padlock.
#
# The CA has to be MINTED as the user first — root only copies the finished
# certificate (a root-side `caddy trust` would leave root-owned files under
# ~/.local/share/caddy that the user unit could no longer write). And minting
# means RUNNING caddy: `caddy trust` does not create a CA offline, it fetches
# the root cert from the admin API of a running instance (verified v2.10.2 —
# an earlier version of this script believed otherwise and the CA never
# landed on a first apply, audit 2026-08-07). caddy-dev.service is
# Type=notify, so the start below blocks until the config is loaded and the
# local CA provisioned; StopWhenUnneeded then reaps the instance once we are
# done with it.
ca_src="$HOME/.local/share/caddy/pki/authorities/local/root.crt"
ca_dst=/etc/pki/ca-trust/source/anchors/caddy-dev-local-ca.crt
if command -v caddy >/dev/null 2>&1; then
  if [ ! -f "$ca_src" ] && systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user start caddy-dev.service 2>/dev/null \
      || warn "could not start caddy-dev.service to mint the CA"
    # Belt and braces: readiness should imply the CA exists, but give the
    # filesystem a moment on a slow first start.
    for _ in 1 2 3 4 5; do
      [ -f "$ca_src" ] && break
      sleep 1
    done
  fi
  if [ -f "$ca_src" ] && stale "$ca_src" "$ca_dst"; then
    add "install -D -m 0644 '$ca_src' '$ca_dst'"
    add "update-ca-trust"
  elif [ ! -f "$ca_src" ]; then
    warn "caddy did not produce a local CA at $ca_src — https://<app>.test will warn until the next apply"
  fi
else
  warn "caddy not installed — no .test web server yet (run 'chezmoi apply' in a terminal so 00-install-packages can install it)"
fi

if [ -n "$root_sh" ]; then
  # set -e seeded at call time, not in $root_sh (the emptiness check above
  # must stay meaningful): without it the joined script returned only the
  # LAST command's status, so a failed dnsmasq restart followed by a clean
  # resolved restart printed the success line below (audit 2026-08-08).
  if run_root /bin/sh -c "set -e
$root_sh"; then
    echo "test-domains: /etc updated (dnsmasq + resolved routing, unprivileged ports, caddy CA)"
  else
    warn "not authorized — /etc parts skipped (rerun 'chezmoi apply' in a terminal)"
  fi
fi

# ------------------------------------------------------------------ user units
systemctl --user daemon-reload 2>/dev/null || { warn "no user manager — sockets not enabled"; exit 0; }

sockets=()
for v in 84 83; do
  if [ -x "/opt/remi/php$v/root/usr/sbin/php-fpm" ]; then
    sockets+=("php$v-fpm-proxy.socket")
  else
    warn "php$v-php-fpm not installed — PHP 8.${v#8} sites will not run (the package is in the manifest; a terminal apply installs it)"
  fi
done

# Only claim 80/443 when there is something behind them AND the kernel will
# actually let a user unit bind them — enabling a socket that cannot bind
# leaves a failed unit and a dead port for every browser request.
port_floor="$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || echo 1024)"
if ! command -v caddy >/dev/null 2>&1; then
  : # already warned above
elif [ "$port_floor" -gt 80 ]; then
  warn "net.ipv4.ip_unprivileged_port_start is $port_floor — 80/443 sockets skipped until the sysctl drop-in lands"
else
  sockets+=(caddy-dev-http.socket caddy-dev-https.socket)
fi

if [ ${#sockets[@]} -gt 0 ]; then
  systemctl --user enable --now "${sockets[@]}" 2>/dev/null \
    && echo "test-domains: listening — ${sockets[*]}" \
    || warn "socket enable failed — check 'systemctl --user status ${sockets[*]}'"
fi

exit 0
