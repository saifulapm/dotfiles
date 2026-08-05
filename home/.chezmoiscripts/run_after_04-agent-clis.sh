#!/usr/bin/env bash
# The agent CLIs this desktop actually uses: claude, codex and copilot feed
# the bar's model-usage widget; pi is swept by bin/codex-usage-scan. All are
# user-local installs (no root), each guarded so re-runs no-op. Their LOGINS
# are interactive and deliberately not scripted — each CLI asks on first run.
#
# voxtype (dictation) has no installer endpoint (voxtype.io/install.sh is a
# 404, verified 2026-08-06) — it stays a manual download; this script only
# finishes its systemd wiring when the binary is already present.
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

# pi installs into the mise-managed node's bin directory, so node must exist —
# 03-dev-toolchain ran first (name order) and put it there.
if command -v mise >/dev/null 2>&1 && mise which node >/dev/null 2>&1; then
  if ! mise exec -- sh -c 'command -v pi' >/dev/null 2>&1; then
    curl -fsSL https://pi.dev/install.sh | sh \
      && echo "agent-clis: pi installed" \
      || warn "pi install failed"
  fi
fi

if command -v voxtype >/dev/null 2>&1; then
  # `voxtype setup systemd` writes the (not chezmoi-managed) user unit
  if [ ! -f "$HOME/.config/systemd/user/voxtype.service" ]; then
    voxtype setup systemd || warn "voxtype setup systemd failed"
  fi
  if systemctl --user is-system-running >/dev/null 2>&1 \
     && ! systemctl --user is-enabled voxtype.service >/dev/null 2>&1; then
    systemctl --user enable --now voxtype.service 2>/dev/null \
      || warn "could not enable voxtype.service"
  fi
else
  warn "voxtype not installed — dictation (Mod+Ctrl+X / F9) stays inert. To enable:"
  warn "  download the binary from github.com/peteonrails/voxtype/releases into ~/.local/bin,"
  warn "  then: voxtype setup --download --model base.en && voxtype setup systemd"
  warn "  and:  systemctl --user enable --now voxtype"
fi

exit 0
