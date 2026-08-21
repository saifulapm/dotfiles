#!/usr/bin/env bash
# gh auth — reinstall the GitHub token from `pass` whenever gh does not have a
# working one. Runs on every apply, so `update-all` (which applies) repairs a
# revoked token by itself instead of leaving it to be found by a 401 weeks
# later, which is exactly how the last one was found (2026-08-21: an error
# body baked into update-all's release-tag state, nine current binaries
# re-downloaded over it).
#
# This can only ever be a REPAIR, never the first install, and the ordering is
# why: the token lives in the password store, and reaching that store needs
# the age key from iCloud, ~/.ssh from the hub blob it decrypts, the store
# clone over ssh, the GPG secret key and its ownertrust — the whole of
# bin/secrets-restore's chain. None of it exists when this runs on a fresh
# machine, and phase 1 has no graphical session to import a GPG key with
# anyway (pinentry-qt with no DISPLAY does not degrade, it ABORTS, and
# `gpg --import` then exits 0 having imported nothing — measured 2026-08-09,
# see the note in secrets-restore). So: a silent no-op on a fresh box,
# self-healing on an established one.
#
# The hard constraint is that an unattended apply must NEVER block. `pass
# show` against a locked key launches pinentry and would stall update-all
# indefinitely, so the read is forced non-interactive with
# --pinentry-mode=error: it succeeds when gpg-agent already holds the key and
# fails instantly when it does not. Timeouts guard every network and store
# call for the same reason, and the script exits 0 unconditionally — gh being
# unauthenticated is not a reason to fail an apply.
set -uo pipefail

warn() { echo "gh-auth: $*" >&2; }

command -v gh   >/dev/null 2>&1 || exit 0
command -v pass >/dev/null 2>&1 || exit 0

# A live API call, not a file check. That is the entire point: `gh auth status`
# fails for a token that EXISTS but has been revoked, which is the case this
# script is here to fix and which a hosts.yml existence test cannot see.
timeout 20 gh auth status >/dev/null 2>&1 && exit 0

# sed -n 1p, never head -1: head closes the pipe at the first line and SIGPIPEs
# pass, which pipefail then reports as failure for a token that was read
# perfectly well.
token="$(PASSWORD_STORE_GPG_OPTS=--pinentry-mode=error \
         timeout 10 pass show github/cli-token 2>/dev/null | sed -n '1p')"
if [ -z "$token" ]; then
  warn "not authenticated, and github/cli-token is not readable without a prompt"
  warn "  (locked gpg key, or no such entry) — run bin/secrets-restore"
  exit 0
fi

if printf '%s\n' "$token" | timeout 30 gh auth login --with-token 2>/dev/null \
   && timeout 20 gh auth status >/dev/null 2>&1; then
  echo "gh-auth: reauthenticated from pass"
else
  # Deliberately not asserting which: an unreachable GitHub and a revoked
  # token fail identically here, and guessing wrong sends you to the wrong fix.
  warn "the token in pass did not authenticate — revoked, or GitHub unreachable"
  warn "  if revoked: regenerate at github.com/settings/tokens (No expiration,"
  warn "  every scope), then: pass edit github/cli-token && pass git push"
fi
exit 0
