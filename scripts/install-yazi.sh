#!/bin/bash
# Install Yazi file manager from GitHub releases
# Downloads pre-built binaries instead of compiling from source

set -e

VERSION="25.5.31"
ARCH=$(uname -m)
INSTALL_DIR="$HOME/.local/bin"

if command -v yazi &>/dev/null; then
    echo "Yazi already installed: $(yazi --version)"
    exit 0
fi

echo "Installing Yazi v${VERSION}..."

mkdir -p "$INSTALL_DIR"

case "$ARCH" in
    x86_64)
        URL="https://github.com/sxyazi/yazi/releases/download/v${VERSION}/yazi-x86_64-unknown-linux-gnu.zip"
        ;;
    aarch64)
        URL="https://github.com/sxyazi/yazi/releases/download/v${VERSION}/yazi-aarch64-unknown-linux-gnu.zip"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

TMP_DIR=$(mktemp -d)
curl -L -o "$TMP_DIR/yazi.zip" "$URL"
unzip -q "$TMP_DIR/yazi.zip" -d "$TMP_DIR"

cp "$TMP_DIR"/yazi-*/yazi "$INSTALL_DIR/"
cp "$TMP_DIR"/yazi-*/ya "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/yazi" "$INSTALL_DIR/ya"

rm -rf "$TMP_DIR"
echo "Yazi installed: $INSTALL_DIR/yazi"
