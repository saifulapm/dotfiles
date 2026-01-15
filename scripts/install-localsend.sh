#!/bin/bash
# Install LocalSend native binary
# Opens GUI with file pre-selected when called with file argument

set -e

# Check for required dependency
if ! ldconfig -p 2>/dev/null | grep -q libayatana-appindicator3; then
    echo "Missing dependency: libayatana-appindicator-gtk3"
    echo "Install with: sudo dnf install libayatana-appindicator-gtk3"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

VERSION="1.17.0"
ARCH=$(uname -m)

case "$ARCH" in
    x86_64) ARCH_NAME="x86-64" ;;
    aarch64) ARCH_NAME="arm-64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

DOWNLOAD_URL="https://github.com/localsend/localsend/releases/download/v${VERSION}/LocalSend-${VERSION}-linux-${ARCH_NAME}.tar.gz"
INSTALL_DIR="$HOME/.local"
TMP_DIR=$(mktemp -d)

echo "Installing LocalSend v${VERSION} (${ARCH_NAME})..."

# Download
echo "Downloading from $DOWNLOAD_URL..."
curl -L -o "$TMP_DIR/localsend.tar.gz" "$DOWNLOAD_URL"

# Extract
echo "Extracting..."
tar -xzf "$TMP_DIR/localsend.tar.gz" -C "$TMP_DIR"

# Install binary and data folder (Flutter app needs the data folder)
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib/localsend"

# Copy binary (named localsend_app in archive)
cp "$TMP_DIR/localsend_app" "$INSTALL_DIR/lib/localsend/"
chmod +x "$INSTALL_DIR/lib/localsend/localsend_app"

# Copy data folder
cp -r "$TMP_DIR/data" "$INSTALL_DIR/lib/localsend/"
cp -r "$TMP_DIR/lib" "$INSTALL_DIR/lib/localsend/" 2>/dev/null || true

# Create wrapper script
cat > "$INSTALL_DIR/bin/localsend" << 'EOF'
#!/bin/bash
LOCALSEND_DIR="$HOME/.local/lib/localsend"
cd "$LOCALSEND_DIR"
exec "$LOCALSEND_DIR/localsend_app" "$@"
EOF
chmod +x "$INSTALL_DIR/bin/localsend"

# Create desktop file
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/localsend.desktop" << EOF
[Desktop Entry]
Name=LocalSend
Comment=Share files locally
Exec=$INSTALL_DIR/bin/localsend
Icon=localsend
Type=Application
Categories=Network;FileTransfer;
Keywords=share;send;transfer;
EOF

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "LocalSend installed successfully!"
echo "Location: $INSTALL_DIR/bin/localsend"
echo ""
echo "Usage: localsend <file>  # Opens GUI with file ready to send"

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
