#!/bin/bash
# Install LocalSend native binary
# - x86_64: AppImage (supports --headless CLI)
# - ARM64: tar.gz (GUI only, no headless)

set -e

VERSION="1.17.0"
ARCH=$(uname -m)
INSTALL_DIR="$HOME/.local"
TMP_DIR=""

cleanup() { [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Installing LocalSend v${VERSION}..."

mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib/localsend"

case "$ARCH" in
    x86_64)
        # AppImage with --headless support
        DOWNLOAD_URL="https://github.com/localsend/localsend/releases/download/v${VERSION}/LocalSend-${VERSION}-linux-x86-64.AppImage"
        echo "Downloading AppImage (x86_64)..."
        curl -L -o "$INSTALL_DIR/bin/localsend" "$DOWNLOAD_URL"
        chmod +x "$INSTALL_DIR/bin/localsend"
        ;;

    aarch64)
        # tar.gz (no AppImage for ARM64)
        DOWNLOAD_URL="https://github.com/localsend/localsend/releases/download/v${VERSION}/LocalSend-${VERSION}-linux-arm-64.tar.gz"
        TMP_DIR=$(mktemp -d)  # Will be cleaned by trap

        echo "Downloading tar.gz (ARM64)..."
        curl -L -o "$TMP_DIR/localsend.tar.gz" "$DOWNLOAD_URL"

        echo "Extracting..."
        tar -xzf "$TMP_DIR/localsend.tar.gz" -C "$TMP_DIR"

        # Install binary and data
        cp "$TMP_DIR/localsend_app" "$INSTALL_DIR/lib/localsend/"
        cp -r "$TMP_DIR/data" "$INSTALL_DIR/lib/localsend/"
        cp -r "$TMP_DIR/lib" "$INSTALL_DIR/lib/localsend/" 2>/dev/null || true
        chmod +x "$INSTALL_DIR/lib/localsend/localsend_app"

        # Create wrapper
        cat > "$INSTALL_DIR/bin/localsend" << 'EOF'
#!/bin/bash
cd "$HOME/.local/lib/localsend"
exec "$HOME/.local/lib/localsend/localsend_app" "$@"
EOF
        chmod +x "$INSTALL_DIR/bin/localsend"

        echo ""
        echo "Note: ARM64 version opens GUI (no --headless support)"
        ;;

    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

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
EOF

echo ""
echo "LocalSend installed: $INSTALL_DIR/bin/localsend"
