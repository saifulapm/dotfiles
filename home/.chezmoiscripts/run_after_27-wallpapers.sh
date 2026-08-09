#!/usr/bin/env bash
# Theme wallpapers — the per-theme background sets, ~100 MB, from our own
# saifulapm/wallpapers repo.
#
# Not a chezmoi external: externals are fetched while chezmoi reads the SOURCE
# STATE, so one GitHub timeout or 5xx on the biggest download in the repo
# aborted `init --apply` before a single package installed or file landed —
# verified in a sandbox, where the whole run died with one bare Go HTTP error
# (audit 2026-08-08). As a script the same failure only warns, the desktop
# merely keeps the wallpapers it already has, and the next apply retries.
#
# Source changed 2026-08-09: this used to pull basecamp/omarchy's whole source
# tarball and throw away everything except themes/*/backgrounds/*. The images
# are now mirrored into our own repo — same bytes, same layout. The point is
# ownership, not bandwidth: the images are most of what omarchy's tarball
# weighs (111 MB there vs 99 MB here, measured), so the saving is ~11%. What
# we actually gain is a set we can add to and remove from, and no pin on
# someone else's repo. The mirror keeps omarchy's MIT LICENSE and credits it
# (CREDITS.md).
#
# It TRACKS MAIN rather than pinning a commit: push a wallpaper to the mirror
# and the next apply on every machine has it, with no commit here. The tradeoff
# is deliberate — machines converge on the latest of a repo we control instead
# of on a fixed point in one we do not. That also rules out a sha256 pin (the
# target moves), so integrity rests on HTTPS plus fetching the exact SHA
# ls-remote just resolved. Extraction lands files as <theme>/backgrounds/<image>,
# the layout bin/background-next and bin/theme-list read. User wallpapers go in
# ~/Pictures/Wallpapers instead; this directory belongs to this script.
#
# Runs before 99-bootstrap-theme by lexical order, so the first theme
# activation has images to point at.
set -uo pipefail

REPO="https://github.com/saifulapm/wallpapers"
BRANCH="main"
dest="$HOME/.local/share/qshell/backgrounds"
stamp="$dest/.rev"

warn() { echo "wallpapers: $*" >&2; }

# Offline, or GitHub down: keep what is on disk and try again next apply.
head="$(git ls-remote "$REPO" "refs/heads/$BRANCH" 2>/dev/null | cut -f1)"
if [ -z "$head" ]; then
  warn "cannot reach $REPO — keeping the wallpapers already on disk"
  exit 0
fi

[ "$(cat "$stamp" 2>/dev/null)" = "$head" ] && exit 0

# Staged as a sibling of dest so the swap below is a same-filesystem rename.
# mktemp's default lives on /tmp, which is tmpfs here: a cross-device mv would
# copy 100 MB instead of renaming, and would not be atomic.
parent="$(dirname "$dest")"
mkdir -p "$parent" || exit 0
tmp="$(mktemp -d "$parent/.backgrounds.XXXXXX")" || exit 0
trap 'rm -rf "$tmp"' EXIT
new="$tmp/x"
mkdir -p "$new"

if ! curl -fsSL -o "$tmp/wallpapers.tar.gz" "$REPO/archive/$head.tar.gz"; then
  warn "fetch failed — keeping the wallpapers already on disk, will retry"
  exit 0
fi

# Repo metadata would otherwise land beside the theme directories.
if ! tar -xzf "$tmp/wallpapers.tar.gz" -C "$new" --strip-components=1 \
  --exclude='*/README.md' --exclude='*/LICENSE' --exclude='*/.gitattributes'; then
  warn "extract failed — keeping the wallpapers already on disk, will retry"
  exit 0
fi

# Never replace a good directory with an empty one: a truncated archive or an
# upstream layout change would otherwise leave the desktop wallpaperless.
if [ -z "$(find "$new" -mindepth 3 -maxdepth 3 -type f -print -quit)" ]; then
  warn "archive has no <theme>/backgrounds/<image> files — keeping what is on disk"
  exit 0
fi

# Stamp inside the tree being swapped in, so the recorded rev and the files it
# describes can never disagree. Swap, rather than the overlay copy this script
# used while pinned: tracking main means images can be REMOVED upstream too,
# and an overlay would leave deleted wallpapers cycling forever.
echo "$head" >"$new/.rev"
old="$tmp/old"
if [ -d "$dest" ] && ! mv "$dest" "$old"; then
  warn "could not move the old wallpapers aside — keeping them, will retry"
  exit 0
fi
if ! mv "$new" "$dest"; then
  # Put the old set back rather than leaving the desktop with no directory.
  [ -d "$old" ] && mv "$old" "$dest"
  warn "could not install the new wallpapers — restored the previous set"
  exit 0
fi

echo "wallpapers: fetched ${head:0:7} from saifulapm/wallpapers"

# Warm the picker thumbnail cache for the new set (the swap gave every file a
# fresh mtime, so every cache key changed). Off the interactive path here so
# the first theme-switcher or wallpaper-picker open never waits on ffmpeg;
# if this is skipped or fails, the pickers generate on demand instead.
find "$dest" -mindepth 3 -maxdepth 3 -type f 2>/dev/null |
  "$HOME/.dotfiles/bin/wallpaper-thumbs" >/dev/null 2>&1 || true

exit 0
