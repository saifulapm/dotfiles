#!/usr/bin/env bash
# Reload gpg-agent when its config actually changed.
#
# gpg-agent reads ~/.gnupg/gpg-agent.conf once, at start, and it is a daemon
# that outlives every apply — so rewriting the file (private_gpg-agent.conf.tmpl)
# does nothing at all until the next login. That is how a machine ends up
# running the OLD pinentry-program with a new config on disk and no sign of it.
#
# Gated on a content hash rather than run every apply, because reloading is not
# free: SIGHUP makes gpg-agent flush every cached passphrase as well as re-read
# the file (gpg-agent(1)), so an unconditional reload would re-lock the agent on
# every `chezmoi apply` and re-prompt for the mail password. Once per real
# change is the honest cost, and the config changes about twice a year.
#
# No sudo anywhere: this is entirely inside the user's own session.
set -uo pipefail

conf="$HOME/.gnupg/gpg-agent.conf"
marker="$HOME/.local/state/gnupg/agent-conf.sha256"

[ -f "$conf" ] || exit 0
command -v gpg-connect-agent >/dev/null 2>&1 || exit 0

have=$(sha256sum "$conf" 2>/dev/null | awk '{print $1}')
[ -n "$have" ] || exit 0
[ "$(cat "$marker" 2>/dev/null)" = "$have" ] && exit 0

# No baseline special-case, deliberately. Recording the hash on a first run
# without reloading looks tidier, but it would skip the reload on exactly the
# apply that needs it most — the one that first ships a new pinentry-program —
# and leave the agent on the old one until the next login, which is precisely
# the "new config on disk, old behaviour in memory" trap this script exists to
# close. The cost of getting it right is one spurious cache flush per machine,
# once, the first time this script runs.
#
# reloadagent starts an agent if none is running, which is fine — a fresh agent
# reads the new config anyway.
if gpg-connect-agent reloadagent /bye >/dev/null 2>&1; then
  mkdir -p "$(dirname "$marker")"
  echo "$have" >"$marker"
  echo "gpg-agent: reloaded (config changed; cached passphrases were flushed)"
else
  echo "gpg-agent: reload failed — the new config lands at next login" >&2
fi

exit 0
