#!/usr/bin/env bash
# workflow (github.com/saifulapm/workflow) — the solo development workflow:
# three Rust binaries out of one checkout, plus the skills, subagents and git
# hook stubs that carry them into a Claude Code session.
#
#   mem       the system of record — facts, rulings, logs, handoffs, questions,
#             roadmaps, plan pages and a wiki of spec pages, kept outside every
#             project
#   workflow  hygiene and lint-msg behind the git hooks, `install`, and `go`,
#             which starts a milestone's orchestrator
#   hub       a web view over mem, tailnet-only, so a phone can follow every
#             project, read its plans and answer its questions
#
# Ours outright, same shape as run_after_45-amx and run_after_36-pxy: clone into
# ~/.local/src/workflow, cargo-build, install into ~/.local/bin. THREE binaries
# from ONE checkout, which is the only way this differs from its siblings — the
# guard and update-all's sweep both hang off `workflow` alone, and the other two
# are rebuilt alongside it. That is deliberate: they share a source tree and a
# revision, so there is no state in which one of them is stale and the others
# are not, and one guard is therefore the honest number.
#
# The skills, the subagents and the git hook stubs ride inside the workflow
# binary; `workflow install` writes them on every apply (see below).
set -uo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

warn() { echo "workflow: $*" >&2; }

src="$HOME/.local/src/workflow"

# ---------------------------------------------------------------- binaries
# Guarded on `workflow` alone; see the header. update-all drops that one
# binary when origin moves, and this block rebuilds all three.
#
# rebuilt tracks whether THIS run replaced the binaries, because the hub
# restart at the bottom must fire on a rebuild and not on the many applies
# that change nothing — bouncing a running service on every `chezmoi apply`
# is a cost with no cause.
rebuilt=0
if [ ! -x "$HOME/.local/bin/workflow" ]; then
  if ! command -v cargo >/dev/null 2>&1; then
    warn "cargo missing (03-dev-toolchain skipped?) — skipping"
    exit 0
  fi

  # rev-parse, not [ -d .git ]: a clone killed mid-transfer must not satisfy
  # the check forever (same guard as amx, nirisaver, pxy and the kakoune fork).
  if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
    rm -rf "$src"
    mkdir -p "$HOME/.local/src"
    git clone --depth 1 https://github.com/saifulapm/workflow "$src" \
      || { warn "clone failed"; exit 0; }
  fi

  echo "workflow: building 3 binaries (first run only — this can take a while)"
  # CARGO_TARGET_DIR inside the checkout so update-all's `rm -f` of the binary
  # forces a reinstall while leaving the build dir for an incremental rebuild.
  # Each crate is its own package (no workspace at the root), so each is built
  # by path; the shared target dir is what keeps the second and third cheap.
  built=1
  for crate in mem workflow hub; do
    if (cd "$src/$crate" && CARGO_TARGET_DIR="$src/build/rust" \
        cargo build --release --quiet); then
      mkdir -p "$HOME/.local/bin"
      install -m755 "$src/build/rust/release/$crate" "$HOME/.local/bin/$crate" \
        || { warn "install of $crate failed"; built=0; }
    else
      warn "build of $crate failed — by hand: cd $src/$crate && CARGO_TARGET_DIR=$src/build/rust cargo build --release"
      built=0
    fi
  done
  if [ "$built" = 1 ]; then
    echo "workflow: installed mem, workflow and hub to ~/.local/bin"
    rebuilt=1
  fi
fi

# ----------------------------------------------------------------- install
# `workflow install` writes the skills into ~/.claude/skills and
# ~/.agents/skills (pi, codex and opencode read it), the subagents into
# ~/.claude/agents and the three git hook stubs into ~/.config/git/hooks, where
# dot_gitconfig's core.hooksPath points every repo, and removes what older
# builds installed. The copies match the installed binary by construction.
# `mem doctor --fix` writes mem's pi extension the same way. Both say nothing
# when nothing changed.
if command -v workflow >/dev/null 2>&1; then
  workflow install >/dev/null 2>&1 \
    || warn "workflow install failed -- an older build? run \`just update-all\`"
fi
if command -v mem >/dev/null 2>&1; then
  mem doctor --fix >/dev/null 2>&1 || true
fi

# ------------------------------------------------------- the retired engine
# workflow.service ran `workflow serve`, the engine the 2026-10-07 rebuild
# removed. chezmoi leaves a deleted source file's target in place, so a machine
# that had the unit still has it, enabled and restarting a verb that no longer
# exists. Stop it and take the file away, once.
unit="$HOME/.config/systemd/user/workflow.service"
if [ -e "$unit" ] || [ -L "$unit" ]; then
  systemctl --user disable --now workflow.service >/dev/null 2>&1 || true
  rm -f "$unit"
  systemctl --user daemon-reload
  echo "workflow: removed the retired workflow.service"
fi

# --------------------------------------------------------------------- hub
# The unit is a chezmoi symlink (dot_config/systemd/user/hub.service),
# ConditionPathExists-gated on the binary. NOT enabled here: hub listens on a
# socket, and switching a network service on across every machine should be a
# per-machine decision, not a side effect of an apply. What this does do is
# keep a hub that is ALREADY running running — a rebuild above replaced the
# binary under it, and the old process is still the old build until restarted.
#
# Gated on `rebuilt`, not just on hub being active: without that this bounces
# the service on every apply, which is a running process interrupted for no
# reason several times a day.
if [ "$rebuilt" = 1 ] && systemctl --user is-active --quiet hub 2>/dev/null; then
  systemctl --user daemon-reload
  systemctl --user restart hub && echo "workflow: hub restarted on the new build"
fi

exit 0
