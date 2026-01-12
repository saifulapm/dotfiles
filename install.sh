#!/bin/bash

# Config - change these
REPO="saiful/dotfiles"
BRANCH="main"

# ─────────────────────────────────────────────────────────────

set -e

DOTFILES="$HOME/.dotfiles"

echo "Cloning dotfiles..."
if [[ -d "$DOTFILES" ]]; then
    git -C "$DOTFILES" pull --quiet
else
    git clone --quiet "https://github.com/$REPO.git" "$DOTFILES"
fi

cd "$DOTFILES"
exec ./setup.sh
