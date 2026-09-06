#!/usr/bin/env bash
# Family DNS helper (decision 2026-09-02): helper machines serve filtered
# DNS to their network — the mini to the office Deco, the MacBook/NUC as a
# roaming/backup layer at home (the home router itself runs OpenWrt with
# native DoH since 2026-09-02, see docs/openwrt-home-2026-09-02.md).
# dnsmasq (run_after_17) forwards everything that is not *.test to the
# uBlockDNS client on 127.0.0.1:53, which filters ads and the YouTube
# block rules over DoH. The account profile ID is a secret (this repo is
# PUBLIC — the ID is the whole key to the DoH endpoint) and lives in
# ~/.config/dns-helper/profile, one line, per machine. The qshell bar's
# dnsshield widget watches the chain on every helper.
#
# A machine runs the filter client iff ~/.config/dns-helper/profile exists
# (the account profile ID, one line — recoverable from the uBlockDNS
# dashboard or `pass show uBlockDNS/profile`). Whether it also SERVES its
# LAN is run_after_17's `serve` marker, independent of this script. On a
# client machine this script bootstraps and keeps: the pinned,
# checksum-verified client binary (github.com/ugzv/ublockdnsclient — we run
# `ublockdns run` under our own unit, deliberately NOT their `ublockdns
# install`, which chattr +i's /etc/resolv.conf and disables the resolved
# stub), the unit, its enablement, and the firewall port. Everyone else:
# quiet skip. Upgrades are manual by design (UBLOCKDNS_NO_AUTOUPDATE=1):
# bump the version+sha pair below, delete the binary, apply.
set -uo pipefail
warn() { echo "ublockdns: $*" >&2; }

profile=$(head -1 "$HOME/.config/dns-helper/profile" 2>/dev/null | tr -cd 'a-z0-9')
[ -n "$profile" ] || exit 0

# The account token (the 4-word one from `pass show uBlockDNS/key`) is
# OPTIONAL for filtering but load-bearing for how fast a rule change lands:
# it subscribes the client to the account's rules stream, which is what makes
# it flush its own DNS cache the moment bin/dns-filter flips a category
# instead of serving the old answer for the rest of a 300 s TTL. Without it
# the client still filters, just with a lag the panel's toggles would wear.
#
# It goes to /etc, not ~/.config, because the unit runs ProtectHome=yes — and
# to a FILE rather than -token on the command line, so it stays out of argv
# and out of `systemctl cat`. 0600 root; the sha256 beside it is the
# world-readable marker this script compares against, since it cannot read
# the token back to check whether it changed.
token=$(head -1 "$HOME/.config/dns-helper/token" 2>/dev/null | tr -d '[:space:]')
token_sha=""
[ -n "$token" ] && token_sha=$(printf '%s' "$token" | sha256sum | awk '{print $1}')

UBLOCKDNS_VERSION="v0.3.0"
UBLOCKDNS_SHA256_ARM64="fa5c07aad44677028890f10b0b4bb5f54dba9a30bc5a90469be6e9461d0b0c33"
UBLOCKDNS_SHA256_AMD64="cbd5739169cec68c13ba310f6cd12d273f6832309cbe70702c450688ff1eb0c4"

run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "ublockdns: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

root_sh=""
add() { root_sh="${root_sh}${1}"$'\n'; }
stale() { ! cmp -s "$1" "$2"; }

# ------------------------------------------------------------- the binary
# Downloaded as the user, verified against the pinned digest, installed by
# the same single root call as everything else. A new architecture means
# adding its digest here, not weakening the check.
if ! command -v ublockdns >/dev/null 2>&1; then
  case "$(uname -m)" in
  aarch64) asset="ublockdns-linux-arm64" expected="$UBLOCKDNS_SHA256_ARM64" ;;
  x86_64) asset="ublockdns-linux-amd64" expected="$UBLOCKDNS_SHA256_AMD64" ;;
  *)
    warn "no pinned digest for $(uname -m) — helper not installed"
    exit 0
    ;;
  esac
  url="https://github.com/ugzv/ublockdnsclient/releases/download/${UBLOCKDNS_VERSION}/${asset}"
  if curl -sSfL -m 120 -o "$tmp/ublockdns" "$url" \
    && [ "$(sha256sum "$tmp/ublockdns" | awk '{print $1}')" = "$expected" ]; then
    add "install -m 0755 '$tmp/ublockdns' /usr/local/bin/ublockdns"
  else
    warn "client ${UBLOCKDNS_VERSION} download/verify failed — helper not installed this apply"
    exit 0
  fi
fi

cat >"$tmp/ublockdns.service" <<'EOF'
# uBlockDNS filtering client on 127.0.0.1:53 (managed by chezmoi, see
# run_after_18-ublockdns.sh). Deliberately NOT `ublockdns install`: their
# installer chattr +i's /etc/resolv.conf, disables the resolved stub, and
# self-updates — this unit runs the same binary in foreground with none of
# that. dnsmasq (127.0.0.2 + wld0) forwards the LAN here; DoH bootstrap uses
# hardcoded public resolvers, so no dependency loop with ourselves.
[Unit]
Description=uBlockDNS DoH filtering client (127.0.0.1:53)
# dnsmasq must be up first so it has already vacated 127.0.0.1:53
After=network.target dnsmasq.service

[Service]
ExecStart=/usr/local/bin/ublockdns run -profile @PROFILE@@TOKENFLAG@
Environment=UBLOCKDNS_NO_AUTOUPDATE=1
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
ProtectHome=yes
ProtectSystem=full
# The binary hardcodes /etc/ublockdns (state) and /var/log/ublockdns.log
ReadWritePaths=/etc/ublockdns /var/log

[Install]
WantedBy=multi-user.target
EOF
sed -i "s|@PROFILE@|$profile|" "$tmp/ublockdns.service"
if [ -n "$token" ]; then
  sed -i "s|@TOKENFLAG@| -token-file /etc/ublockdns/token|" "$tmp/ublockdns.service"
else
  sed -i "s|@TOKENFLAG@||" "$tmp/ublockdns.service"
fi
chmod 0644 "$tmp"/ublockdns.service

# Rotating the token changes neither the unit nor its enablement, so it needs
# its own staleness test — and its own restart, since `enable --now` on an
# already-running unit would leave the client holding the old one.
token_stale=""
if [ -n "$token" ] && [ "$(cat /etc/ublockdns/token.sha256 2>/dev/null)" != "$token_sha" ]; then
  token_stale=yes
  printf '%s\n' "$token" >"$tmp/token"
  printf '%s\n' "$token_sha" >"$tmp/token.sha256"
fi

# is-active in the gate, 17's lesson: a unit that enabled but failed to
# start must keep being retried by later applies, not pass silently.
unit_stale=""
stale "$tmp/ublockdns.service" /etc/systemd/system/ublockdns.service && unit_stale=yes

if [ -n "$unit_stale" ] || [ -n "$token_stale" ] \
  || ! systemctl is-enabled --quiet ublockdns 2>/dev/null \
  || ! systemctl is-active --quiet ublockdns 2>/dev/null; then
  add "mkdir -p /etc/ublockdns"
  if [ -n "$token_stale" ]; then
    add "install -m 0600 '$tmp/token' /etc/ublockdns/token"
    add "install -m 0644 '$tmp/token.sha256' /etc/ublockdns/token.sha256"
  fi
  add "install -D -m 0644 '$tmp/ublockdns.service' /etc/systemd/system/ublockdns.service"
  add "systemctl daemon-reload"
  add "systemctl enable --now ublockdns.service"
  # Only when the CONTENT changed: try-restart is a no-op on a stopped unit,
  # and restarting the client drops LAN DNS for about a second, so it must not
  # ride along on an apply that merely re-asserted enablement.
  if [ -n "$unit_stale" ] || [ -n "$token_stale" ]; then
    add "systemctl try-restart ublockdns.service"
  fi
fi

# The LAN cannot query a closed port. The query side is unprivileged
# (verified 2026-09-02), so a consistent machine stays prompt-free — only
# the fix needs root.
if ! firewall-cmd --quiet --zone=public --query-service=dns 2>/dev/null; then
  add "firewall-cmd --permanent --zone=public --add-service=dns && firewall-cmd --reload"
fi

if [ -n "$root_sh" ]; then
  if run_root /bin/sh -c "set -e
$root_sh"; then
    echo "ublockdns: /etc consistent (unit, enablement, firewall)"
  else
    warn "not authorized — skipped (rerun 'chezmoi apply' in a terminal)"
  fi
fi

exit 0
