#!/bin/bash
# Build LocalSend from source (for ARM64 with --headless support)
# https://github.com/localsend/localsend

set -e

INSTALL_DIR="$HOME/.local"
BUILD_DIR="$HOME/.cache/localsend-build"
FLUTTER_VERSION="3.25.0"

echo "=== LocalSend Build Script ==="
echo ""

# Install dependencies
install_deps() {
    local packages=(
        git curl clang cmake ninja-build pkg-config
        gtk3-devel libayatana-appindicator-gtk3-devel
    )

    echo "Installing build dependencies..."
    sudo dnf install -y "${packages[@]}"
}

# Install Flutter
install_flutter() {
    if [[ -d "$HOME/.flutter" ]]; then
        echo "Flutter already installed at ~/.flutter"
        export PATH="$HOME/.flutter/bin:$PATH"
        return
    fi

    echo "Installing Flutter ${FLUTTER_VERSION}..."
    cd "$HOME"
    git clone https://github.com/flutter/flutter.git -b stable .flutter
    export PATH="$HOME/.flutter/bin:$PATH"
    flutter precache
    flutter doctor
}

# Install Rust
install_rust() {
    if command -v rustc &>/dev/null; then
        echo "Rust already installed: $(rustc --version)"
        return
    fi

    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
}

# Build LocalSend
build_localsend() {
    echo ""
    echo "=== Building LocalSend ==="

    # Clone or update
    if [[ -d "$BUILD_DIR/localsend" ]]; then
        echo "Updating LocalSend source..."
        cd "$BUILD_DIR/localsend"
        git pull
    else
        echo "Cloning LocalSend..."
        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"
        git clone --depth 1 https://github.com/localsend/localsend.git
    fi

    cd "$BUILD_DIR/localsend/app"

    # Get dependencies
    echo "Getting Flutter dependencies..."
    flutter pub get

    # Build
    echo "Building Linux release..."
    flutter build linux --release

    echo "Build complete!"
}

# Install built binary
install_binary() {
    echo ""
    echo "=== Installing LocalSend ==="

    BUILD_OUTPUT="$BUILD_DIR/localsend/app/build/linux/arm64/release/bundle"

    # Check if build exists (might be in different arch folder)
    if [[ ! -d "$BUILD_OUTPUT" ]]; then
        BUILD_OUTPUT="$BUILD_DIR/localsend/app/build/linux/$(uname -m)/release/bundle"
    fi
    if [[ ! -d "$BUILD_OUTPUT" ]]; then
        BUILD_OUTPUT=$(find "$BUILD_DIR/localsend/app/build/linux" -name "bundle" -type d | head -1)
    fi

    if [[ ! -d "$BUILD_OUTPUT" ]]; then
        echo "Build output not found!"
        exit 1
    fi

    # Install to ~/.local/lib/localsend
    mkdir -p "$INSTALL_DIR/lib/localsend"
    mkdir -p "$INSTALL_DIR/bin"

    cp -r "$BUILD_OUTPUT"/* "$INSTALL_DIR/lib/localsend/"
    chmod +x "$INSTALL_DIR/lib/localsend/localsend"

    # Create wrapper script
    cat > "$INSTALL_DIR/bin/localsend" << 'EOF'
#!/bin/bash
LOCALSEND_DIR="$HOME/.local/lib/localsend"
cd "$LOCALSEND_DIR"
exec "$LOCALSEND_DIR/localsend" "$@"
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
EOF

    echo ""
    echo "LocalSend installed successfully!"
    echo "Location: $INSTALL_DIR/bin/localsend"
    echo ""
    echo "Test with: localsend --help"
}

# Main
install_deps

echo ""
install_flutter

echo ""
install_rust

build_localsend
install_binary

echo ""
echo "=== Done ==="
echo "You can remove the build cache with: rm -rf $BUILD_DIR"
