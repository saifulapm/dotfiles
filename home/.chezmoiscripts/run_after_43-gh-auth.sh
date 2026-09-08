#!/usr/bin/env bash
# gh auth — reinstall the GitHub token from `pass` whenever gh does not have a
# working one. Runs on every apply, so `update-all` (which applies) repairs a
# revoked token by itself instead of leaving it to be found by a 401 weeks
# later, which is exactly how the last one was found (2026-08-21: an error
# body baked into update-all's release-tag state, nine current binaries
# re-downloaded over it).
#
# TWO ACCOUNTS since 2026-09-09 (saifulapm personal, lareysbd commercial), and
# the repair is deliberately PER ACCOUNT. A bare `gh auth status` exits 1 when
# ANY account is unhealthy, so the single check this script used to open with
# would answer "broken" for a perfectly good personal token the moment the
# commercial one lapsed — and then reinstall the personal one, which was never
# the problem, while the actual dead token stayed dead. The JSON form below
# gives one row per account with a `state` that is the result of a real API
# call, and (unlike the plain form) exits 0 regardless, so a broken account
# arrives as data rather than as an error to interpret.
#
# This can only ever be a REPAIR, never the first install, and the ordering is
# why: the tokens live in the password store, and reaching that store needs
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

# account:pass-entry. saifulapm keeps the unsuffixed entry it has always had —
# renaming it for symmetry would mean a store edit on three machines to buy
# nothing.
accounts="saifulapm:github/cli-token lareysbd:github/cli-token-lareysbd"

# One invocation, one round trip per token, both answers at once: `state` is
# live (a token that EXISTS but was revoked reports failure here, which a
# hosts.yml existence test cannot see) and `active` is the pointer this script
# must put back afterwards. Empty output — no auth at all, or gh refusing to
# report on an empty hosts.yml — reads as "every account needs installing",
# which is correct.
states="$(timeout 20 gh auth status --json hosts \
          --jq '.hosts["github.com"][]? | "\(.login):\(.state):\(.active)"' \
          2>/dev/null | tr '\n' ' ')"

# Whichever account was active BEFORE any repair. Restored rather than forced
# to saifulapm: a `gh lareys` the user ran deliberately five minutes ago must
# survive an unattended apply that happened to renew a token.
active_before=""
for s in $states; do
  case "$s" in *:true) active_before="${s%%:*}" ;; esac
done

repaired=0
for pair in $accounts; do
  user="${pair%%:*}"
  entry="${pair#*:}"

  case " $states " in *" $user:success:"*) continue ;; esac

  # sed -n 1p, never head -1: head closes the pipe at the first line and
  # SIGPIPEs pass, which pipefail then reports as failure for a token that was
  # read perfectly well.
  token="$(PASSWORD_STORE_GPG_OPTS=--pinentry-mode=error \
           timeout 10 pass show "$entry" 2>/dev/null | sed -n '1p')"
  if [ -z "$token" ]; then
    warn "$user is not authenticated, and $entry is not readable without a prompt"
    warn "  (locked gpg key, or no such entry) — run bin/secrets-restore"
    continue
  fi

  if printf '%s\n' "$token" | timeout 30 gh auth login --with-token 2>/dev/null; then
    repaired=1
    echo "gh-auth: reauthenticated $user from pass"
  else
    # Deliberately not asserting which: an unreachable GitHub and a revoked
    # token fail identically here, and guessing wrong sends you to the wrong
    # fix.
    warn "the token in $entry did not authenticate — revoked, or GitHub unreachable"
    warn "  if revoked: regenerate at github.com/settings/tokens as $user"
    warn "  (No expiration, every scope), then: pass edit $entry && pass git push"
  fi
  unset token
done

# `gh auth login --with-token` makes the account it just installed ACTIVE.
# Left alone, renewing the commercial token would silently repoint every later
# bare `gh` command at lareysbd — a 404 on the next personal repo, with an
# apply nobody was watching as the only cause. Only ever run after a repair,
# so this cannot fight a deliberate switch it had no part in.
if [ "$repaired" = 1 ]; then
  want="${active_before:-saifulapm}"
  active_now="$(timeout 20 gh auth status --json hosts \
                --jq '.hosts["github.com"][]? | select(.active) | .login' 2>/dev/null)"
  if [ -n "$active_now" ] && [ "$active_now" != "$want" ]; then
    timeout 20 gh auth switch --hostname github.com --user "$want" >/dev/null 2>&1 \
      && echo "gh-auth: active account restored to $want"
  fi
fi
exit 0
