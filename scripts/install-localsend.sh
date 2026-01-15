#!/bin/bash
# Install LocalSend with --headless CLI support
# - x86_64: Downloads AppImage (pre-built)
# - ARM64: Builds from source (no pre-built AppImage available)

set -e

ARCH=$(uname -m)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$ARCH" in
    x86_64)
        # x86_64 has pre-built AppImage with --headless support
        VERSION="1.17.0"
        DOWNLOAD_URL="https://github.com/localsend/localsend/releases/download/v${VERSION}/LocalSend-${VERSION}-linux-x86-64.AppImage"
        INSTALL_DIR="$HOME/.local"

        echo "Installing LocalSend v${VERSION} AppImage..."
        mkdir -p "$INSTALL_DIR/bin"
        curl -L -o "$INSTALL_DIR/bin/localsend" "$DOWNLOAD_URL"
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
EOF

        echo ""
        echo "LocalSend installed successfully!"
        echo "Location: $INSTALL_DIR/bin/localsend"
        ;;

    aarch64)
        # ARM64 needs to build from source (no AppImage available)
        echo "ARM64 detected - building from source for --headless support"
        echo ""
        exec "$SCRIPT_DIR/build-localsend.sh"
        ;;

    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo ""
echo "Usage:"
echo "  localsend                    # Open GUI"
echo "  localsend --headless <file>  # CLI mode (no GUI)"
