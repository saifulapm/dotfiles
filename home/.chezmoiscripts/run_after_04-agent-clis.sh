#!/usr/bin/env bash
# The agent CLIs this desktop actually uses: claude, codex and copilot feed
# the bar's model-usage widget; pi is swept by bin/codex-usage-scan; fx feeds
# neither widget nor sweep and is here on its own merits. All are user-local
# installs (no root), each guarded so re-runs no-op. Their LOGINS are
# interactive and deliberately not scripted — each CLI asks on first run.
#
# voxtype (dictation) used to be wired up at the end of this script because it
# was a hand install. It is scripted now — binary, model and systemd unit —
# in run_after_01-voxtype.sh, which runs before 02 owns the unit's state.
#
# Failures warn instead of aborting so a flaky network cannot stop the rest
# of a fresh-machine apply.
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"

warn() { echo "agent-clis: $*" >&2; }

if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash \
    && echo "agent-clis: claude installed (run 'claude' once to log in)" \
    || warn "claude install failed"
fi

if ! command -v codex >/dev/null 2>&1; then
  curl -fsSL https://chatgpt.com/codex/install.sh | sh \
    && echo "agent-clis: codex installed (run 'codex' once to log in)" \
    || warn "codex install failed"
fi

if ! command -v copilot >/dev/null 2>&1; then
  curl -fsSL https://gh.io/copilot-install | bash \
    && echo "agent-clis: copilot installed (run 'copilot' once to log in)" \
    || warn "copilot install failed"
fi

# fx (Vercel Labs, written in Zig) — a model-agnostic agent harness: `fx` for
# a session, `fx ask` for one noninteractive request, `fx acp` to serve it
# over stdio. Installed 2026-08-26.
#
# THE `export PATH` AT THE TOP IS LOAD-BEARING FOR THIS ONE, where for the
# three above it is only a guard convenience. fx's setup.sh ends by checking
# whether its install dir is on PATH and, when it is not, APPENDS a PATH line
# to the rc file for $SHELL — which here is fish, whose config.fish is a
# chezmoi symlink INTO THIS REPO. That append would land in the source tree
# and leave the repo dirty on every machine that applied: the same trap
# documented at run_after_45-amx for `amx doctor --fix`. With ~/.local/bin
# exported above the check passes and no rc file is touched (verified
# 2026-08-26 — install ran, `git status` stayed clean).
#
# Auth is a first-run decision and not scripted, like the three above:
# `fx login` for Vercel AI Gateway, or `fx provider codex|grok` to ride a
# subscription that is already logged in. Neither is required to USE it here —
# `pxy launch fx` wires it to 127.0.0.1:4100 through FX_GATEWAY_* plus pxy's
# own local api_key, which short-circuits fx's credential chain, so the
# proxy's ~30 providers answer with no Vercel account existing at all and no
# gateway traffic leaving the machine. State (settings.json, sessions,
# mcp.json, usage) lives in ~/.fx, which on Linux holds the API key in
# plaintext — deliberately unmanaged, and never a candidate for this repo.
#
# Install-only guard: fx ships `fx upgrade`, and bin/update-all runs it, so
# rerunning the installer here would be a slower second path to the same
# binary. Stdout is dropped because the noninteractive installer echoes the
# bare install path; its "installed fx <version>" line goes to stderr and stays.
if ! command -v fx >/dev/null 2>&1; then
  curl -fsSL https://fx.sh/setup.sh | bash >/dev/null \
    && echo "agent-clis: fx installed (run 'fx login', or just 'pxy launch fx')" \
    || warn "fx install failed"
fi

# pi installs into the mise-managed node's bin directory, so node must exist —
# 03-dev-toolchain ran first (name order) and put it there.
#
# The installer runs UNDER `mise exec`, not bare (fixed 2026-08-10). Its
# preflight is a plain `command -v node`, and a chezmoi run script inherits
# only the PATH of whatever invoked `chezmoi apply` — no mise activation. Apply
# from an interactive shell (the dev MacBook) and mise's node is already on
# PATH, so this worked; apply from the fresh-install bootstrap (the NUC) and it
# is not, so the installer offered to fetch its OWN standalone node, unpacked
# ~200 MB into ~/.local/share/pi-node and installed pi under that — a second
# node runtime this repo does not manage, on a PATH nothing adds, so the guard
# below never saw the pi it had just installed and every apply reran it.
if command -v mise >/dev/null 2>&1 && mise which node >/dev/null 2>&1; then
  if ! mise exec -- sh -c 'command -v pi' >/dev/null 2>&1; then
    mise exec -- sh -c 'curl -fsSL https://pi.dev/install.sh | sh' \
      && echo "agent-clis: pi installed" \
      || warn "pi install failed"
  fi
fi

# Leftover from a pre-2026-08-10 apply (see above). Flagged, never deleted:
# it is a user-writable data dir, and the reclaim is the user's call.
if [ -d "$HOME/.local/share/pi-node" ]; then
  warn "~/.local/share/pi-node is a stale standalone node from an older pi install —"
  warn "  pi now lives next to the mise node; 'rm -rf ~/.local/share/pi-node' reclaims the space"
fi

exit 0
