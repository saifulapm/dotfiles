#!/bin/bash
# Install LocalSend native binary (for headless CLI support)
# This replaces the flatpak version with native binary

set -e

VERSION="1.17.0"
ARCH=$(uname -m)

case "$ARCH" in
    x86_64) ARCH_NAME="x86-64" ;;
    aarch64) ARCH_NAME="arm-64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

DOWNLOAD_URL="https://github.com/localsend/localsend/releases/download/v${VERSION}/LocalSend-${VERSION}-linux-${ARCH_NAME}.tar.gz"
INSTALL_DIR="$HOME/.local/bin"
TMP_DIR=$(mktemp -d)

echo "Installing LocalSend v${VERSION} (${ARCH_NAME})..."

# Download
echo "Downloading from $DOWNLOAD_URL..."
curl -L -o "$TMP_DIR/localsend.tar.gz" "$DOWNLOAD_URL"

# Extract
echo "Extracting..."
tar -xzf "$TMP_DIR/localsend.tar.gz" -C "$TMP_DIR"

# Install binary
mkdir -p "$INSTALL_DIR"
cp "$TMP_DIR/localsend" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/localsend"

# Install desktop file and icon if they exist
if [[ -f "$TMP_DIR/localsend.desktop" ]]; then
    mkdir -p "$HOME/.local/share/applications"
    cp "$TMP_DIR/localsend.desktop" "$HOME/.local/share/applications/"
fi

if [[ -d "$TMP_DIR/data/flutter_assets/assets" ]]; then
    mkdir -p "$HOME/.local/share/icons/hicolor/512x512/apps"
    find "$TMP_DIR" -name "*.png" -path "*icon*" -exec cp {} "$HOME/.local/share/icons/hicolor/512x512/apps/localsend.png" \; 2>/dev/null || true
fi

# Cleanup
rm -rf "$TMP_DIR"

# Verify installation
if command -v localsend &>/dev/null; then
    echo "LocalSend installed successfully!"
    echo "Location: $(which localsend)"
    echo ""
    echo "You can now use: localsend --help"
    echo "Headless mode: localsend send <file>"
else
    echo "Installation complete. Add ~/.local/bin to PATH if not already."
    echo "LocalSend binary: $INSTALL_DIR/localsend"
fi

# Optional: Remove flatpak version
if flatpak list 2>/dev/null | grep -q "org.localsend.localsend_app"; then
    echo ""
    read -p "Remove flatpak version? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        flatpak uninstall -y org.localsend.localsend_app
        echo "Flatpak version removed."
    fi
fi
