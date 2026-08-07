#!/usr/bin/env bash
# Herd-style https://<project>.test (decision 2026-08-07). Three moving parts,
# and only the first of them is ever running:
#
#   1. dnsmasq answers *.test with 127.0.0.1 on 127.0.0.1:5353, and a
#      systemd-resolved drop-in routes the `test` domain there. This is the
#      one always-on piece — ~2 MB, and DNS cannot be socket-activated on
#      demand because resolved needs an answer before anything connects.
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

cat >"$tmp/dnsmasq.conf" <<'EOF'
# *.test → this machine, for the Herd-style dev domains (managed by chezmoi,
# see run_after_17-test-domains.sh).
#
# Port 5353 rather than 53: systemd-resolved already owns 53, and this is a
# stub that only ever answers `test`. Verified 2026-08-07 that binding
# 127.0.0.1:5353 succeeds alongside avahi-daemon's 0.0.0.0:5353 mDNS socket
# (both set SO_REUSEADDR) and that unicast queries reach the more specific
# bind, i.e. dnsmasq and not avahi.
address=/test/127.0.0.1
listen-address=127.0.0.1
port=5353
bind-interfaces

# A resolver for one hardcoded answer has no business reading /etc/resolv.conf
# or forwarding anything upstream.
no-resolv
no-hosts
EOF

cat >"$tmp/resolved.conf" <<'EOF'
# Route the `test` domain to the dnsmasq stub on 5353 (managed by chezmoi,
# see run_after_17-test-domains.sh). The ~ prefix makes this a ROUTING-only
# domain: it sends *.test lookups to dnsmasq without making it a search
# suffix or the default resolver for anything else.
[Resolve]
DNS=127.0.0.1:5353
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
  if stale "$tmp/dnsmasq.conf" /etc/dnsmasq.d/test-domains.conf \
    || stale "$tmp/resolved.conf" /etc/systemd/resolved.conf.d/test-domains.conf \
    || ! systemctl is-enabled --quiet dnsmasq 2>/dev/null; then
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
# NOT `caddy trust` in the root call: that command reads and, if absent,
# CREATES the CA in whatever HOME it is run under. As root it would either
# mint a second CA in /root or — with HOME pointed at the user — leave
# root-owned files in ~/.local/share/caddy that caddy-dev.service (a user
# unit) could no longer write. So the CA is minted as the user below, and
# root only copies the finished certificate.
ca_src="$HOME/.local/share/caddy/pki/authorities/local/root.crt"
ca_dst=/etc/pki/ca-trust/source/anchors/caddy-dev-local-ca.crt
if command -v caddy >/dev/null 2>&1; then
  if [ ! -f "$ca_src" ]; then
    # Mints the CA under the user's own storage. The trust-store half of this
    # command needs root and will fail here — that is fine and expected, the
    # root call below is what installs it.
    caddy trust >/dev/null 2>&1 || true
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
  if run_root /bin/sh -c "$root_sh"; then
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
