#!/bin/bash

# Config
REPO="saifulapm/dotfiles"
BRANCH="main"

# ─────────────────────────────────────────────────────────────

set -e

DOTFILES="$HOME/.dotfiles"

echo "Cloning dotfiles..."
if [[ -d "$DOTFILES/.git" ]]; then
    # Fetch latest and reset to origin
    git -C "$DOTFILES" fetch --quiet origin
    git -C "$DOTFILES" reset --hard --quiet origin/$BRANCH
else
    rm -rf "$DOTFILES"
    git clone --quiet "https://github.com/$REPO.git" "$DOTFILES"
fi

cd "$DOTFILES"
exec ./setup.sh
