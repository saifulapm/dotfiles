#!/bin/bash
# Install Yazi file manager from GitHub releases
# Downloads pre-built binaries instead of compiling from source

set -e

UPDATE_MODE=false
[[ "$1" == "--update" ]] && UPDATE_MODE=true

ARCH=$(uname -m)
INSTALL_DIR="$HOME/.local/bin"
TMP_DIR=""

cleanup() { [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Get latest version from GitHub API
VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')

if [[ -z "$VERSION" ]]; then
    echo "Failed to fetch latest version"
    exit 1
fi

if command -v yazi &>/dev/null && [[ "$UPDATE_MODE" == "false" ]]; then
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
curl -sL -o "$TMP_DIR/yazi.zip" "$URL"
unzip -q "$TMP_DIR/yazi.zip" -d "$TMP_DIR"

cp "$TMP_DIR"/yazi-*/yazi "$INSTALL_DIR/"
cp "$TMP_DIR"/yazi-*/ya "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/yazi" "$INSTALL_DIR/ya"

# Install plugins from package.toml
if [[ -f "$HOME/.config/yazi/package.toml" ]]; then
    "$INSTALL_DIR/ya" pkg install 2>/dev/null || true
fi

echo "Yazi installed: $INSTALL_DIR/yazi"
