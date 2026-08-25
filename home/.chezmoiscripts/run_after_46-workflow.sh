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
# The skills are symlinked rather than copied (amx's SKILL.md is copied — this
# is the deliberate difference): seven skill directories that co-evolve with
# three binaries must not be able to drift from the revision that built them.
# A copy would need hand-refreshing seven times and would silently describe a
# binary that is no longer installed.
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

# ------------------------------------------------------------------ skills
# Seven symlinks into the checkout's skills/, so a session loads exactly the
# instructions that match the installed binaries.
#
# THE DEV BOX IS THE EXCEPTION, and it is resolved here rather than left as a
# caveat the way pxy's and amx's are: on the machine where ~/Sites/github/
# workflow is the working copy, the links point THERE, so editing a skill
# takes effect in the next session instead of after a push and an update-all.
# Every other machine gets the built checkout. Both are the same repo; only
# the revision differs, and on the dev box the working copy is the one that
# should win.
skills_src="$src/skills"
[ -d "$HOME/Sites/github/workflow/skills" ] \
  && skills_src="$HOME/Sites/github/workflow/skills"

if [ -d "$skills_src" ]; then
  mkdir -p "$HOME/.claude/skills"
  for skill in "$skills_src"/*/; do
    skill="${skill%/}" # the glob's trailing slash, off the link target
    name="$(basename "$skill")"
    dest="$HOME/.claude/skills/$name"
    # Only ever replace a symlink or a missing entry. A real directory there
    # is somebody's own skill (or a chezmoi-managed one like amx/ and
    # desktop/) and is never clobbered by this loop.
    if [ -L "$dest" ] || [ ! -e "$dest" ]; then
      # Quiet when it already points where it should: this loop runs on every
      # apply so that a skill added upstream appears without ceremony, and an
      # apply that changed nothing should say nothing.
      [ "$(readlink "$dest" 2>/dev/null)" = "$skill" ] && continue
      ln -sfn "$skill" "$dest" && linked=$((${linked:-0} + 1))
    else
      warn "$dest is a real directory — leaving it alone"
    fi
  done
  [ "${linked:-0}" -gt 0 ] \
    && echo "workflow: linked ${linked} skill(s) from $skills_src"
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
