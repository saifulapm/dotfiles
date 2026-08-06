#!/usr/bin/env bash
# Herd-like on-demand dev services (decision 2026-08-07): podman quadlet
# containers (~/.config/containers/systemd/*.container) behind
# systemd-socket-proxyd pairs (~/.config/systemd/user/*-proxy.*). The
# sockets hold the standard ports at ~0 RAM; the first connection starts
# the container, 10 minutes idle stops it again (StopWhenUnneeded).
# This script reloads units, pre-pulls missing images (so first use is not
# a surprise ~700 MB download) and lights the sockets. Warn-don't-abort.
set -uo pipefail
warn() { echo "dev-services: $*" >&2; }

command -v podman >/dev/null 2>&1 || { warn "podman missing — skipped"; exit 0; }

systemctl --user daemon-reload 2>/dev/null || { warn "no user manager — skipped"; exit 0; }

images=(
  docker.io/library/mysql:8.4
  docker.io/library/postgres:18
  docker.io/library/redis:7
  docker.io/axllent/mailpit:latest
)
for img in "${images[@]}"; do
  if ! podman image exists "$img"; then
    podman pull -q "$img" >/dev/null \
      && echo "dev-services: pulled $img" \
      || warn "pull $img failed (offline?) — the first socket hit will retry"
  fi
done

sockets=(
  mysql84-proxy.socket
  postgres18-proxy.socket
  redis7-proxy.socket
  mailpit-smtp-proxy.socket
  mailpit-web-proxy.socket
)
systemctl --user enable --now "${sockets[@]}" 2>/dev/null \
  || warn "socket enable failed — check systemctl --user status"

exit 0
