#!/usr/bin/env bash
# Build the vicinae TypeScript extensions in vicinae/*/ into
# ~/.local/share/vicinae/extensions/, which is where the server looks for
# them. Currently one: vicinae/youtube (docs/youtube-2026-09-06.md).
#
# WHY A BUILD STEP AT ALL, when everything else here is either an rpm or a
# file chezmoi copies into place. A vicinae extension is not source that the
# server reads: `vici build` typechecks it, bundles each command through
# esbuild into one CJS file per command, and copies the manifest and assets
# beside them. The alternative was committing that bundle — minified
# JavaScript in the dotfiles, rebuilt by hand and diffed by nobody — so the
# source is what lives in the repo and every machine builds its own.
#
# WHY NOT `chezmoi apply`'s source directory. The extension is a node project:
# it has a package.json that is ALSO vicinae's manifest, a lockfile, and a
# node_modules that must not be managed. Under home/ chezmoi would try to own
# all of it. So it sits at the repo top level beside shell/ and packages/,
# like every other thing here that is built rather than copied, and this
# script reaches it through CHEZMOI_WORKING_TREE.
#
# Rebuild is mtime-gated against a stamp outside the output directory — `vici
# build` writes its result by renaming a staging directory over the old one,
# so a stamp kept inside would be deleted by the very build that set it.
#
# Warn-don't-abort throughout: a machine with no node yet (a fresh apply where
# run_after_03 has not finished, or ran offline) should still get the rest of
# the desktop. The launcher works without the extension; it just does not list
# the YouTube commands.
set -uo pipefail

warn() { echo "vicinae-extensions: $*" >&2; }

src_root="$CHEZMOI_WORKING_TREE/vicinae"
[ -d "$src_root" ] || exit 0

# mise's shims are on the user manager's PATH but not necessarily on the PATH
# an interactive `chezmoi apply` inherits.
export PATH="$HOME/.local/share/mise/shims:$PATH"

for dep in node npm; do
  command -v "$dep" >/dev/null 2>&1 || {
    warn "$dep missing — extensions not built (rerun 'chezmoi apply' after run_after_03 installs node)"
    exit 0
  }
done

state="$HOME/.local/state/qshell"
mkdir -p "$state"
built_any=0

for src in "$src_root"/*/; do
  [ -f "$src/package.json" ] || continue
  name="$(basename "$src")"
  stamp="$state/vicinae-ext-$name.stamp"
  out="$HOME/.local/share/vicinae/extensions/$name"

  # -quit on the first hit: this is a "has anything changed" question, not a
  # list. node_modules is pruned because npm rewrites mtimes in there on every
  # install, which would make the answer permanently yes.
  if [ -d "$out" ] && [ -e "$stamp" ] &&
    [ -z "$(find "$src" -name node_modules -prune -o -newer "$stamp" -print -quit 2>/dev/null)" ]; then
    continue
  fi

  # npm ci, not install: the lockfile is committed precisely so that every
  # machine resolves the same three dev dependencies, and ci fails loudly when
  # the lock and the manifest disagree instead of quietly rewriting the lock.
  if ! (cd "$src" && npm ci --silent >/dev/null 2>&1); then
    warn "npm ci failed for $name (offline?) — skipping"
    continue
  fi

  if (cd "$src" && ./node_modules/.bin/vici build >/dev/null 2>&1); then
    touch "$stamp"
    built_any=1
    echo "vicinae-extensions: built $name"
  else
    # Re-run visibly: a typecheck failure is a real error and its message is
    # the only useful thing this script can print.
    warn "build failed for $name:"
    (cd "$src" && ./node_modules/.bin/vici build 2>&1 | tail -20) >&2
  fi
done

# The server scans the extensions directory at startup, so a newly built
# extension is not listed until it restarts. Also self-heals the other half of
# this feature: vicinae.service dropped --no-extension-runtime on 2026-09-06,
# and a session still running the old command line has no node process to run
# any of this — no extension manager while extensions exist means the unit on
# disk and the process are out of step.
session_up() {
  systemctl --user -q is-active graphical-session.target 2>/dev/null
}

if session_up && systemctl --user -q is-active vicinae.service 2>/dev/null; then
  if [ "$built_any" = 1 ] || ! pgrep -f 'vicinae/extension-manager\.js' >/dev/null 2>&1; then
    systemctl --user restart vicinae.service 2>/dev/null \
      || warn "could not restart vicinae — run: systemctl --user restart vicinae"
  fi
fi

exit 0
