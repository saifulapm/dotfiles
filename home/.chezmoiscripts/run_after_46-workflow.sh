#!/usr/bin/env bash
# workflow (github.com/saifulapm/workflow) — the solo development workflow:
# three Rust binaries out of one checkout, plus the session-facing skills that
# carry them into a Claude Code session.
#
#   mem       the system of record — facts, rulings, logs, handoffs, blocking
#             questions, and a wiki of design pages, kept outside every project
#   workflow  the gate and the orchestrator — verify, lint-msg, review-needed,
#             plan-driven run, status, reap, park/resume, doctor
#   hub       a web view over mem's question queue, tailnet-only, so a blocking
#             question can be answered from a phone
#
# Ours outright, same shape as run_after_45-amx and run_after_36-pxy: clone into
# ~/.local/src/workflow, cargo-build, install into ~/.local/bin. THREE binaries
# from ONE checkout, which is the only way this differs from its siblings — the
# guard and update-all's sweep both hang off `workflow` alone, and the other two
# are rebuilt alongside it. That is deliberate: they share a source tree and a
# revision, so there is no state in which one of them is stale and the others
# are not, and one guard is therefore the honest number.
#
# The skills and the git hook stubs are copies `workflow doctor --fix` writes
# from the binary they ride in, so a machine's copies match its installed
# workflow by construction; the doctor block below runs it on every apply.
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

# ------------------------------------------------------------ doctor --fix
# The eight skills and the three git hook stubs ride inside the workflow
# binary since m1-harness (2026-09-15): `workflow doctor --fix` writes copies
# into ~/.claude/skills, ~/.agents/skills (pi, codex and opencode read it) and
# ~/.config/git/hooks, and `workflow doctor` reports a copy that drifted from
# the binary. A copy matches the installed binary by construction, which is
# what the symlink loop this replaced was for -- and the loop never delivered
# the hook stubs to any machine but the dev box. `mem doctor --fix` writes
# mem's pi extension the same way. Both say nothing when nothing changed.
if command -v workflow >/dev/null 2>&1; then
  workflow doctor --fix >/dev/null 2>&1 \
    || warn "workflow doctor --fix left findings -- run \`workflow doctor\` by hand"
fi
if command -v mem >/dev/null 2>&1; then
  mem doctor --fix >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------- hooks
# The three git hook stubs, symlinked into ~/.config/git/hooks/, where
# dot_gitconfig's core.hooksPath points every repo on the machine. The same
# dev-box rule as the skills: the working copy's stubs where it exists, the
# built checkout's everywhere else. Only a symlink or a missing entry is ever
# replaced; a real file there is somebody's own hook. Until 2026-09-13 this
# had been done by hand on the MacBook and nowhere else, and since the stubs
# fail open by design, the NUC's gate stood open without a word.
hooks_src="$src/hooks"
[ -d "$HOME/Sites/github/workflow/hooks" ] \
  && hooks_src="$HOME/Sites/github/workflow/hooks"
if [ -d "$hooks_src" ]; then
  mkdir -p "$HOME/.config/git/hooks"
  for hook in pre-commit commit-msg pre-push; do
    dest="$HOME/.config/git/hooks/$hook"
    [ "$(readlink "$dest" 2>/dev/null)" = "$hooks_src/$hook" ] && continue
    if [ -L "$dest" ] || [ ! -e "$dest" ]; then
      ln -sfn "$hooks_src/$hook" "$dest" && echo "workflow: linked git hook $hook"
    else
      warn "$dest is a real file — leaving it alone"
    fi
  done
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
