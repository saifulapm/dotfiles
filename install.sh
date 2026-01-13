#!/bin/bash

# Config
REPO="saifulapm/dotfiles"
BRANCH="main"

# ─────────────────────────────────────────────────────────────

set -e

DOTFILES="$HOME/.dotfiles"

echo "Cloning dotfiles..."
if [[ -d "$DOTFILES/.git" ]]; then
    # Reset local changes and pull latest
    git -C "$DOTFILES" reset --hard --quiet
    git -C "$DOTFILES" pull --quiet
else
    rm -rf "$DOTFILES"
    git clone --quiet "https://github.com/$REPO.git" "$DOTFILES"
fi

cd "$DOTFILES"
exec ./setup.sh
