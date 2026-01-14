#!/bin/bash
# Setup GNOME/GTK initial configuration
# - Sets default GTK theme and color scheme
# - Fixes Nautilus icon compatibility with Yaru theme
# - Updates icon caches

set -e

echo "Setting up GNOME/GTK configuration..."

# ─────────────────────────────────────────────────────────────
# Set initial GNOME theme settings
# ─────────────────────────────────────────────────────────────
if command -v gsettings &>/dev/null; then
    echo "  Setting GTK theme to Adwaita-dark..."
    gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark" 2>/dev/null || true

    echo "  Setting color scheme to prefer-dark..."
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true

    echo "  Setting icon theme to Yaru-purple..."
    gsettings set org.gnome.desktop.interface icon-theme "Yaru-purple" 2>/dev/null || true

    echo "  Setting font preferences..."
    gsettings set org.gnome.desktop.interface font-name "Liberation Sans 11" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface monospace-font-name "Maple Mono 10" 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────
# Fix Nautilus icon compatibility with Yaru theme
# ─────────────────────────────────────────────────────────────
YARU_ACTIONS="/usr/share/icons/Yaru/scalable/actions"
ADWAITA_ACTIONS="/usr/share/icons/Adwaita/symbolic/actions"

if [[ -d "$ADWAITA_ACTIONS" ]] && [[ -d "/usr/share/icons/Yaru" ]]; then
    echo "  Fixing Nautilus navigation icons..."

    # Create actions directory if it doesn't exist
    if [[ ! -d "$YARU_ACTIONS" ]]; then
        sudo mkdir -p "$YARU_ACTIONS"
    fi

    # Symlink navigation icons from Adwaita to Yaru
    for icon in go-previous-symbolic.svg go-next-symbolic.svg; do
        if [[ -f "$ADWAITA_ACTIONS/$icon" ]] && [[ ! -e "$YARU_ACTIONS/$icon" ]]; then
            sudo ln -snf "$ADWAITA_ACTIONS/$icon" "$YARU_ACTIONS/$icon"
            echo "    Linked $icon"
        fi
    done
fi

# ─────────────────────────────────────────────────────────────
# Update icon caches
# ─────────────────────────────────────────────────────────────
echo "  Updating icon caches..."
if [[ -d "/usr/share/icons/Yaru" ]]; then
    sudo gtk-update-icon-cache /usr/share/icons/Yaru 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────
# Update fontconfig cache
# ─────────────────────────────────────────────────────────────
echo "  Updating fontconfig cache..."
fc-cache -f 2>/dev/null || true

echo "GNOME/GTK configuration complete!"
