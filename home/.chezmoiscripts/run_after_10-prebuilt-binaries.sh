#!/usr/bin/env bash
# Tools Fedora does not package whose upstreams ship linux binaries for both
# our arches (asset names verified against the GitHub API 2026-08-07, jj and
# witr 2026-08-08): watchexec, hurl, cloudflared, stripe, ouch, usql, jj, witr.
# Everything lands in ~/.local/bin; guarded per binary; warn-don't-abort.
#
# GitHub's unauthenticated API allows 60 requests/hour per IP — eight here, and
# only on a run where something is actually missing (fully-guarded runs make
# no requests at all).
set -uo pipefail

warn() { echo "prebuilt: $*" >&2; }
bindir="$HOME/.local/bin"
mkdir -p "$bindir"

arch="$(uname -m)"   # aarch64 | x86_64

# latest_asset <owner/repo> <asset-regex> → download URL on stdout, or nothing
latest_asset() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
    | jq -r --arg re "$2" '.assets[] | select(.name | test($re)) | .browser_download_url' \
    | head -1
}

# fetch_tar <owner/repo> <asset-regex> <member-name> <dest-bin>
# Downloads the tarball, extracts the one named binary from anywhere in the
# archive, installs it executable.
fetch_tar() {
  local url; url="$(latest_asset "$1" "$2")"
  [ -z "$url" ] && { warn "$4: no release asset matched $2"; return 1; }
  local tmp; tmp="$(mktemp -d)"
  ( cd "$tmp" \
    && curl -fsSL -o archive "$url" \
    && case "$url" in
         *.tar.xz)  tar -xJf archive ;;
         *.tar.bz2) tar -xjf archive ;;
         *)         tar -xzf archive ;;
       esac \
    && found="$(find . -type f -name "$3" | head -1)" \
    && [ -n "$found" ] \
    && install -m755 "$found" "$bindir/$4" )
  local rc=$?
  rm -rf "$tmp"
  [ $rc -eq 0 ] && echo "prebuilt: installed $4" || warn "$4 install failed"
  return $rc
}

if ! command -v watchexec >/dev/null 2>&1; then
  fetch_tar watchexec/watchexec "watchexec-.*-${arch}-unknown-linux-gnu\\.tar\\.xz$" watchexec watchexec
fi

if ! command -v hurl >/dev/null 2>&1; then
  fetch_tar Orange-OpenSource/hurl "hurl-.*-${arch}-unknown-linux-gnu\\.tar\\.gz$" hurl hurl
fi

if ! command -v cloudflared >/dev/null 2>&1; then
  # cloudflared ships a bare binary, not a tarball, and names arches the
  # go way (arm64/amd64).
  goarch="arm64"; [ "$arch" = "x86_64" ] && goarch="amd64"
  url="$(latest_asset cloudflare/cloudflared "^cloudflared-linux-${goarch}$")"
  if [ -n "$url" ] && curl -fsSL -o "$bindir/cloudflared.tmp" "$url"; then
    install -m755 "$bindir/cloudflared.tmp" "$bindir/cloudflared" && rm -f "$bindir/cloudflared.tmp"
    echo "prebuilt: installed cloudflared"
  else
    rm -f "$bindir/cloudflared.tmp"; warn "cloudflared install failed"
  fi
fi

if ! command -v stripe >/dev/null 2>&1; then
  # stripe names arches arm64/x86_64.
  sarch="arm64"; [ "$arch" = "x86_64" ] && sarch="x86_64"
  fetch_tar stripe/stripe-cli "stripe_.*_linux_${sarch}\\.tar\\.gz$" stripe stripe
fi

# ouch (yazi extract opener) — the cargo build needs libclang, so the
# release binary is the mechanism.
if ! command -v ouch >/dev/null 2>&1; then
  fetch_tar ouch-org/ouch "ouch-${arch}-unknown-linux-gnu\\.tar\\.gz$" ouch ouch
fi

# usql (universal SQL CLI, config in ~/.config/usql) — go-style arch names;
# deliberately NOT the usql_static variant (regular build has the common
# drivers at half the size)
if ! command -v usql >/dev/null 2>&1; then
  goarch="arm64"; [ "$arch" = "x86_64" ] && goarch="amd64"
  fetch_tar xo/usql "usql-.*-linux-${goarch}\\.tar\\.bz2$" usql usql
fi

# jj (Jujutsu) — git-compatible VCS, colocated by default since 0.39 so it
# rides an existing .git without converting it. musl is the only linux build
# upstream ships; it is fully static, which is what we want here anyway.
if ! command -v jj >/dev/null 2>&1; then
  fetch_tar jj-vcs/jj "jj-.*-${arch}-unknown-linux-musl\\.tar\\.gz$" jj jj
fi

# witr — "why is this running?": traces a process/port/container/file back to
# whatever started it. Ships a bare binary with go-style arch names, plus a
# man page we install alongside it (nothing else here has one to follow).
if ! command -v witr >/dev/null 2>&1; then
  goarch="arm64"; [ "$arch" = "x86_64" ] && goarch="amd64"
  url="$(latest_asset pranshuparmar/witr "^witr-linux-${goarch}$")"
  if [ -n "$url" ] && curl -fsSL -o "$bindir/witr.tmp" "$url"; then
    install -m755 "$bindir/witr.tmp" "$bindir/witr" && rm -f "$bindir/witr.tmp"
    manurl="$(latest_asset pranshuparmar/witr "^witr\\.1$")"
    if [ -n "$manurl" ]; then
      mkdir -p "$HOME/.local/share/man/man1"
      curl -fsSL -o "$HOME/.local/share/man/man1/witr.1" "$manurl" || true
    fi
    echo "prebuilt: installed witr"
  else
    rm -f "$bindir/witr.tmp"; warn "witr install failed"
  fi
fi

exit 0
