#!/usr/bin/env bash
# Build vicinae from source with packages/vicinae-tab-fallback.patch applied,
# so Tab runs the first fallback command from root search on every machine.
#
# WHY A BUILD STEP, when vicinae is an rpm from COPR and everything else here
# is a package or a file chezmoi copies. The behaviour cannot be configured:
# vicinae's Keybind enum is a closed list of 22 actions with no "run this
# command" among them, so `keybinds` can rebind Tab but has nothing to bind it
# TO. The 31-line patch adds one enum entry and handles it beside the existing
# Space alias-fast-track. Carrying the patch as source and compiling per
# machine is the same trade as vicinae/youtube next door: the repo holds
# something reviewable, not a committed binary.
#
# ORDERING: sorts before run_after_53-vicinae-extensions, which is what we
# want — the extensions build against whatever vicinae is installed, and the
# server restart at the end of a build should happen before extensions are
# rebuilt into its extension dir.
#
# WARN-DON'T-ABORT, and deliberately so: this is the most expensive script in
# the apply (a cold build is minutes), and it is also the most skippable. A
# machine that fails here still has a launcher, because
# home/dot_config/systemd/user/vicinae.service runs bin/vicinae-serve, which
# execs the packaged /usr/bin/vicinae whenever the local build is absent. The
# cost of failure is one keybind, not the desktop.
#
# The real work lives in bin/vicinae-rebuild --if-needed, which no-ops unless
# the built server is missing the patch or the stamp (tag + patch checksum)
# has moved. Editing the patch therefore triggers exactly one rebuild on the
# next apply, on every machine.
set -uo pipefail

warn() { echo "vicinae-build: $*" >&2; }

rebuild="$CHEZMOI_WORKING_TREE/bin/vicinae-rebuild"
[ -x "$rebuild" ] || exit 0

# No vicinae package means this is not a desktop box (or 00-install-packages
# has not run yet); nothing to patch and nothing to fall back to.
rpm -q vicinae >/dev/null 2>&1 || exit 0

for dep in git cmake ninja; do
  command -v "$dep" >/dev/null 2>&1 || {
    warn "$dep missing — skipping (rerun after 00-install-packages lands)"
    exit 0
  }
done

"$rebuild" --if-needed || warn "build failed — launcher stays on the packaged binary; retry with \`vicinae-rebuild\`"

exit 0
