#!/bin/bash
# Setup GNOME/GTK initial configuration
# - Sets default GTK theme and color scheme
# - Fixes Yaru icon theme inheritance for Fedora
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
# Fix Yaru icon theme inheritance (Fedora compatibility)
# ─────────────────────────────────────────────────────────────
# Yaru inherits from "Humanity" which doesn't exist on Fedora
# Replace with Adwaita for proper icon fallback (all variants)
if [[ -d "/usr/share/icons/Yaru" ]]; then
    if grep -q ",Humanity," /usr/share/icons/Yaru*/index.theme 2>/dev/null; then
        echo "  Fixing Yaru icon theme inheritance (Humanity -> Adwaita)..."
        sudo sed -i 's/,Humanity,/,Adwaita,/g' /usr/share/icons/Yaru*/index.theme
    fi
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
