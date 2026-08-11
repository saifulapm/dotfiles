#!/usr/bin/env bash
# playwright-cli — the browser the agent drives (decision 2026-08-11).
#
# Chosen over the MCP server as the default channel because a CLI costs no
# context until it is used, while an MCP server's tool definitions are loaded
# into every session whether or not a browser is involved. It also carries
# more than the MCP surface: video, tracing, network mocking, cookie/storage
# access and mouse press/release. `install --skills --global` drops the
# Playwright team's own SKILL.md into ~/.claude/skills/playwright-cli, so the
# command reference updates with the package instead of rotting in our repo.
#
# Two machine facts shape the config (home/dot_config/playwright-cli):
# Google ships no Chrome for Linux arm64, and Playwright's bundled builds are
# compiled against Ubuntu — so both roads lead to Fedora's own chromium via
# launchOptions.executablePath. Without that, `open` dies looking for
# /opt/google/chrome/chrome.
#
# Warn-don't-abort like its neighbours: a flaky registry must not stop the
# rest of a fresh-machine apply.
set -uo pipefail

export PATH="$HOME/.local/share/pnpm/bin:$PATH"

command -v pnpm >/dev/null 2>&1 || exit 0   # node toolchain not up yet

warn() { echo "playwright-cli: $*" >&2; }

if ! command -v playwright-cli >/dev/null 2>&1; then
  pnpm add -g @playwright/cli@latest \
    || { warn "install failed"; exit 0; }
fi

# The skill is the CLI's own documentation; refresh it whenever the package
# is newer than the installed copy so the two cannot drift.
skill="$HOME/.claude/skills/playwright-cli/SKILL.md"
if [ ! -f "$skill" ] || [ "$(command -v playwright-cli)" -nt "$skill" ]; then
  playwright-cli install --skills --global >/dev/null 2>&1 \
    || warn "could not install the playwright-cli skill"
fi
