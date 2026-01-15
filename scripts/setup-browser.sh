#!/bin/bash
# Setup browser configuration

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

# Link chromium flags
ln -sf "$DOTFILES/config/chromium-flags.conf" ~/.config/chromium-flags.conf

# Create chromium config directory
mkdir -p ~/.config/chromium/Default

# Copy default preferences if not exists
if [[ ! -f ~/.config/chromium/Default/Preferences ]]; then
    cp "$DOTFILES/config/chromium/Default/Preferences" ~/.config/chromium/Default/
fi

echo "Browser setup complete"
echo "Extension will load from: $DOTFILES/default/chromium/extensions/copy-url"
