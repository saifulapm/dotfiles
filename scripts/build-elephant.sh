#!/bin/bash
# Build elephant and providers from source
# Elephant is the data provider backend for walker

set -e

ELEPHANT_DIR="$HOME/.local/share/elephant-src"
PROVIDERS_DIR="$HOME/.config/elephant/providers"
BIN_DIR="$HOME/.local/bin"

# Ensure Go is installed
if ! command -v go &>/dev/null; then
    echo "Error: Go is required to build elephant"
    echo "Install with: sudo dnf install golang"
    exit 1
fi

# Ensure bin directory exists
mkdir -p "$BIN_DIR"

# Clone/update elephant
if [[ -d "$ELEPHANT_DIR" ]]; then
    echo "Updating elephant source..."
    cd "$ELEPHANT_DIR"
    git pull
else
    echo "Cloning elephant..."
    git clone https://github.com/abenz1267/elephant "$ELEPHANT_DIR"
    cd "$ELEPHANT_DIR"
fi

# Build main binary
echo "Building elephant..."
cd cmd
go build -o elephant elephant.go
cp elephant "$BIN_DIR/"
echo "Installed: $BIN_DIR/elephant"

# Build providers
mkdir -p "$PROVIDERS_DIR"
cd ../internal/providers

# All providers except archlinuxpkgs (Arch-specific)
PROVIDERS=(
    desktopapplications
    files
    bluetooth
    clipboard
    runner
    symbols
    calc
    menus
    providerlist
    websearch
    todo
    bookmarks
    unicodes
    windows
    snippets
    nirisessions
    onepassword
)

echo ""
echo "Building providers..."
for provider in "${PROVIDERS[@]}"; do
    if [[ -d "$provider" ]]; then
        echo "  Building: $provider"
        cd "$provider"
        go build -buildmode=plugin 2>/dev/null || {
            echo "    Warning: Failed to build $provider (may not exist yet)"
            cd ..
            continue
        }
        cp "${provider}.so" "$PROVIDERS_DIR/"
        cd ..
    else
        echo "  Skipping: $provider (directory not found)"
    fi
done

echo ""
echo "Elephant build complete!"
echo "Binary: $BIN_DIR/elephant"
echo "Providers: $PROVIDERS_DIR/"
echo ""
echo "To enable the service, run:"
echo "  elephant service enable"
echo "  systemctl --user start elephant.service"
