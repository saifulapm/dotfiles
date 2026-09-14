#!/usr/bin/env bash
# qmd (tobi/qmd) — local hybrid document search: BM25 + vectors + LLM rerank
# over the collections in dot_config/qmd/index.yml, in one SQLite file under
# ~/.cache/qmd. Two things read it: the AI Chat command in vicinae/ai-ask,
# over MCP (dot_config/vicinae/ai-ask-mcp.json spawns `qmd mcp`), and
# `qmd query "…"` from a shell. docs/qmd-2026-09-14.md is the write-up.
#
# NOT the npm package. Upstream qmd only runs local GGUF models, which on a
# GPU-less machine (no Vulkan build of node-llama-cpp for linux-arm64) means
# a second per embedded chunk and minutes per reranked query. The fork at
# github.com/saifulapm/qmd, branch remote-models, adds an OpenAI-compatible
# backend and index.yml points it at pxy — embeds in seconds, no 2 GB of
# model downloads. Until upstream takes it (PR.md in the fork), every
# machine builds the fork:
#
#   clone/fetch the branch into ~/.local/share/qmd/src
#   npm install            (dev deps; npm 7+ pulls the typescript peer)
#   node scripts/build.mjs (stamps the commit into dist/build-info.json)
#   npm pack + npm install -g <tarball>
#
# Why a tarball and not `npm install -g github:…`: the package's `prepare`
# hook builds with tsc, and a git install never sees the typescript peer, so
# it dies with MODULE_NOT_FOUND (verified 2026-09-14). A packed tarball has
# dist/ inside and runs no hooks. Idempotent: `qmd --version` reports the
# stamped commit and the install is skipped when it matches the clone's
# HEAD. Offline: the fetch is allowed to fail and whatever is checked out is
# built, so a machine without network keeps the qmd it has.
#
# An npm global under the mise node, guarded the way run_after_04 guards pi
# — against the ACTIVE node's bin dir, because a `node = "lts"` bump gives a
# fresh empty lib/node_modules and the stale shim would satisfy
# `command -v qmd` forever.
#
# npm 11's install-scripts policy skips the six native postinstalls
# (node-llama-cpp, five tree-sitter grammars) with a warning. qmd works
# without them: the grammars ship prebuilds and node-llama-cpp is never
# loaded with the remote backend (verified 2026-09-14). So no --allow-scripts.
#
# Indexing is NOT done here. run_after_02 enables qmd-refresh.timer, whose
# service runs `qmd update` and `qmd embed` hourly with ConditionPathExists on
# the shim this script creates; the kick at the end starts the first run in
# the background. Warn-don't-abort throughout, as everything else here.
set -uo pipefail

warn() { echo "qmd: $*" >&2; }

QMD_REPO="https://github.com/saifulapm/qmd.git"
QMD_BRANCH="remote-models"
QMD_SRC="$HOME/.local/share/qmd/src"

if ! command -v mise >/dev/null 2>&1 || ! mise which node >/dev/null 2>&1; then
  warn "no mise node yet — skipped (rerun 'chezmoi apply' after run_after_03 installs it)"
  exit 0
fi

if [ -d "$QMD_SRC/.git" ]; then
  git -C "$QMD_SRC" fetch -q origin "$QMD_BRANCH" \
    && git -C "$QMD_SRC" checkout -q -B "$QMD_BRANCH" FETCH_HEAD \
    || warn "fetch of $QMD_BRANCH failed (offline?) — building what is checked out"
else
  mkdir -p "$(dirname "$QMD_SRC")"
  if ! git clone -q --branch "$QMD_BRANCH" --depth 1 "$QMD_REPO" "$QMD_SRC"; then
    warn "clone of $QMD_REPO failed (offline?)"
    exit 0
  fi
fi

qmd_bin="$(mise where node)/bin/qmd"
want="$(git -C "$QMD_SRC" rev-parse --short HEAD)"
have="$([ -x "$qmd_bin" ] && "$qmd_bin" --version 2>/dev/null | sed -n 's/.*(\([0-9a-f]*\)).*/\1/p')"

if [ "$have" != "$want" ]; then
  if (cd "$QMD_SRC" \
      && mise exec -- npm install --no-audit --no-fund >/dev/null 2>&1 \
      && mise exec -- node scripts/build.mjs >/dev/null 2>&1 \
      && rm -f ./*.tgz \
      && mise exec -- npm pack >/dev/null 2>&1 \
      && mise exec -- npm install -g ./tobilu-qmd-*.tgz >/dev/null 2>&1); then
    echo "qmd: installed $("$qmd_bin" --version 2>/dev/null) from $QMD_BRANCH"
  else
    warn "build/install of the fork failed — cd $QMD_SRC and run the steps by hand"
    exit 0
  fi
fi

# The shim is what the units and the MCP entry call; mise writes it on
# install, but a reshim is cheap and repairs the case where it did not.
mise reshim >/dev/null 2>&1 || true

if systemctl --user -q is-enabled qmd-refresh.timer 2>/dev/null; then
  systemctl --user start --no-block qmd-refresh.service 2>/dev/null \
    || warn "could not start qmd-refresh.service — journalctl --user -u qmd-refresh"
fi

exit 0
