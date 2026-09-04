#!/usr/bin/env bash
# Sweeps dangling symlinks left behind by removed features.
#
# THE BUG CLASS, which this repo has now hit four times: deleting a file from
# the source state does NOT delete the copy in $HOME. chezmoi stops managing
# it and walks away, and in symlink mode that leaves a symlink pointing at a
# repo path that no longer exists. Nothing ever cleans those up, and they are
# not always inert — fish sources ~/.config/fish/completions on every prompt,
# so a dangling completion keeps offering subcommands for a deleted command.
#
# What it clears today (105 links, found 2026-09-04 by sweeping rather than by
# remembering, which is the point):
#   * audio-heal          146f867  .service, .timer, 99-homepod-raop.conf
#   * aichat              212e40c  99 links: the whole ~/.config/aichat tree,
#                                  its kak autoload file and a fish function
#   * screensaver         c6f621b  foot/screensaver.ini
#                         f69d82b  qshell/screensaver-quotes.txt
#   * text-size           b857b32  fish completion — the actively harmful one
#
# WHY A PREDICATE RATHER THAN A LIST OF PATHS, which is what run_after_39/41/44
# do: those name their targets because each cleans up after ONE feature it was
# written alongside. This is the general case, and after four rounds of the
# same mistake a list would just be the fifth. The predicate below is exact
# rather than broad — a symlink that dangles AND whose target lies inside this
# repo is the precise signature of "chezmoi managed this and the source is
# gone", and there is no legitimate state in which such a link should exist.
# Measured on this machine when it was written: 5495 symlinks under the roots
# below, 105 matched, and the live ones (~/.config/quickshell -> the shell
# tree, every themed config) were correctly untouched because they RESOLVE.
#
# A user's own symlink to somewhere outside the repo can never match, and
# neither can a broken link into /usr or /opt — those are somebody else's
# problem and are deliberately left alone.
#
# run_after_, not run_once_after_, for the reason run_after_39 spells out: a
# run_once_ script is recorded as done the first time it runs, and the other
# two machines have not applied this yet. The sweep IS the state — on a clean
# machine it is one find over four directories and exits having done nothing.
set -uo pipefail

repo="$HOME/.dotfiles"
removed=0
declare -a parents=()

# Bounded on purpose. These are the only trees chezmoi deploys into with
# symlinks; sweeping $HOME wholesale would drag in caches, build trees and
# every project checkout for no gain.
roots=()
for root in "$HOME/.config" "$HOME/.local/share" "$HOME/.local/state" "$HOME/.local/bin"; do
  [ -d "$root" ] && roots+=("$root")
done

if [ "${#roots[@]}" -gt 0 ]; then
  # Collect first, delete after: removing entries while find is still walking
  # the same directories is how a sweep misses half its targets.
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    target="$(readlink "$link" 2>/dev/null)" || continue
    # chezmoi writes ABSOLUTE targets, so a prefix test is enough and is
    # tighter than resolving — a dangling path cannot be resolved anyway.
    case "$target" in
    "$repo"/*) ;;
    *) continue ;;
    esac
    if rm -f "$link" 2>/dev/null; then
      removed=$((removed + 1))
      parents+=("$(dirname "$link")")
    fi
  done < <(find "${roots[@]}" -xtype l 2>/dev/null)
fi

# Directories the deletions just emptied — the aichat tree is 20-odd nested
# ones. `rmdir -p` walks upward and --ignore-fail-on-non-empty makes it stop
# at the first directory that still holds something, so it can never climb out
# of the tree it started in (~/.config is never empty).
if [ "${#parents[@]}" -gt 0 ]; then
  while IFS= read -r dir; do
    [ -d "$dir" ] || continue
    rmdir -p --ignore-fail-on-non-empty "$dir" 2>/dev/null
  done < <(printf '%s\n' "${parents[@]}" | sort -ru)
fi

[ "$removed" -gt 0 ] && echo "stale-links: removed $removed dangling symlink(s) into the repo"

# aichat's binary, which 212e40c meant to retire and did not: the commit
# dropped the config, the kak plugin, the fish widget and the prebuilt-binary
# INSTALL, but nothing uninstalled the copy already sitting in ~/.local/bin.
# Guarded on the path so a deliberate reinstall is not fought over on every
# apply — if it comes back on purpose, drop this block with it.
if [ -f "$HOME/.local/bin/aichat" ]; then
  rm -f "$HOME/.local/bin/aichat" && echo "stale-links: removed the orphaned aichat binary (212e40c retired it)"
fi

exit 0
