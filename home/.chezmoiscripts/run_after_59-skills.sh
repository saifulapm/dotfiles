#!/usr/bin/env bash
# Saiful's agent skills (github.com/saifulapm/skills, private) — his own
# skills plus the ones it vendors from anthropics, antfu, mattpocock and
# others (skills.lock.json there says which). Cloned into ~/.local/src/skills
# and each skills/<name>/ linked into the two places agents look:
#
#   ~/.claude/skills/<name>   Claude Code
#   ~/.agents/skills/<name>   pi, codex and opencode
#
# Symlinks into the checkout, not copies and not the repo's own
# `npx skills add`: an update is the checkout moving and nothing else, there
# is no CLI to fetch, and nothing keeps a second lock. `just update-all`
# fetches and resets the checkout (its source-build sweep); this script only
# clones when it is missing, so a plain apply never moves it — same contract
# as the amx and workflow clones.
#
# Runs on every apply: it links skills the repo gained and removes our links
# to skills it dropped. It never replaces a path it did not create — workflow
# install writes real directories into the same two places, and a name clash
# is reported, not resolved. The clone goes through the user's git config,
# which sends github.com/saifulapm over SSH, so a machine without its key yet
# warns and skips like everything else here.
set -uo pipefail

warn() { echo "skills: $*" >&2; }

src="$HOME/.local/src/skills"

command -v git >/dev/null 2>&1 || { warn "git missing — skipped"; exit 0; }

# rev-parse, not [ -d .git ] — a killed clone passes the directory test.
if ! git -C "$src" rev-parse HEAD >/dev/null 2>&1; then
  rm -rf "$src"
  mkdir -p "$(dirname "$src")"
  git clone -q --depth 1 https://github.com/saifulapm/skills "$src" \
    || { warn "clone failed (no SSH key for github.com yet?)"; exit 0; }
  echo "skills: cloned $(git -C "$src" rev-parse --short HEAD)"
fi

linked=0 pruned=0
for dest in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  mkdir -p "$dest"

  for skill in "$src"/skills/*/; do
    skill="${skill%/}"
    [ -f "$skill/SKILL.md" ] || continue
    name="$(basename "$skill")" link="$dest/$name"
    if [ -L "$link" ]; then
      [ "$(readlink "$link")" = "$skill" ] && continue
      case "$(readlink "$link")" in
      "$src"/*) ;; # ours, pointing somewhere stale — repoint it
      *) warn "$link is someone else's link — left alone"; continue ;;
      esac
    elif [ -e "$link" ]; then
      warn "$link already exists (another installer's?) — left alone"
      continue
    fi
    ln -sfn "$skill" "$link" && linked=$((linked + 1))
  done

  # Our links whose skill the repo no longer has.
  for link in "$dest"/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
    "$src"/skills/*) [ -e "$link" ] || { rm -f "$link" && pruned=$((pruned + 1)); } ;;
    esac
  done
done

[ "$linked" -gt 0 ] && echo "skills: linked $linked"
[ "$pruned" -gt 0 ] && echo "skills: removed $pruned link(s) to skills the repo dropped"

exit 0
