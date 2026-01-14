#!/bin/bash
# Setup Maple Mono and Nerd Fonts Symbols Only
# Downloads latest versions from GitHub releases

set -e

FONTS_DIR="$HOME/.local/share/fonts"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Ensure fonts directory exists
mkdir -p "$FONTS_DIR"

echo "Setting up fonts..."

# Get latest Maple Mono release version
echo ""
echo "Fetching latest Maple Mono release..."
MAPLE_VERSION=$(curl -sL "https://api.github.com/repos/subframe7536/maple-font/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$MAPLE_VERSION" ]]; then
    echo "Error: Could not determine Maple Mono version"
    exit 1
fi

echo "Latest Maple Mono version: $MAPLE_VERSION"

# Download Maple Mono fonts
MAPLE_BASE_URL="https://github.com/subframe7536/maple-font/releases/download/$MAPLE_VERSION"

echo "Downloading MapleMono-TTF.zip..."
curl -sL "$MAPLE_BASE_URL/MapleMono-TTF.zip" -o "$TEMP_DIR/MapleMono-TTF.zip"

echo "Downloading MapleMono-NF-unhinted.zip..."
curl -sL "$MAPLE_BASE_URL/MapleMono-NF-unhinted.zip" -o "$TEMP_DIR/MapleMono-NF-unhinted.zip"

# Get latest Nerd Fonts release version
echo ""
echo "Fetching latest Nerd Fonts release..."
NERD_VERSION=$(curl -sL "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$NERD_VERSION" ]]; then
    echo "Error: Could not determine Nerd Fonts version"
    exit 1
fi

echo "Latest Nerd Fonts version: $NERD_VERSION"

# Download Nerd Fonts Symbols Only
NERD_BASE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_VERSION"

echo "Downloading NerdFontsSymbolsOnly.zip..."
curl -sL "$NERD_BASE_URL/NerdFontsSymbolsOnly.zip" -o "$TEMP_DIR/NerdFontsSymbolsOnly.zip"

# Extract fonts
echo ""
echo "Extracting fonts..."

# Create subdirectories for organization
mkdir -p "$FONTS_DIR/MapleMono"
mkdir -p "$FONTS_DIR/MapleMono-NF"
mkdir -p "$FONTS_DIR/NerdFontsSymbolsOnly"

# Extract Maple Mono TTF
unzip -q -o "$TEMP_DIR/MapleMono-TTF.zip" -d "$TEMP_DIR/maple-ttf"
find "$TEMP_DIR/maple-ttf" -name "*.ttf" -exec cp {} "$FONTS_DIR/MapleMono/" \;

# Extract Maple Mono Nerd Font
unzip -q -o "$TEMP_DIR/MapleMono-NF-unhinted.zip" -d "$TEMP_DIR/maple-nf"
find "$TEMP_DIR/maple-nf" -name "*.ttf" -exec cp {} "$FONTS_DIR/MapleMono-NF/" \;

# Extract Nerd Fonts Symbols Only
unzip -q -o "$TEMP_DIR/NerdFontsSymbolsOnly.zip" -d "$TEMP_DIR/nerd-symbols"
find "$TEMP_DIR/nerd-symbols" -name "*.ttf" -exec cp {} "$FONTS_DIR/NerdFontsSymbolsOnly/" \;

# Update font cache
echo ""
echo "Updating font cache..."
fc-cache -f

# Show installed fonts
echo ""
echo "Fonts installed successfully!"
echo ""
echo "Maple Mono:"
ls -1 "$FONTS_DIR/MapleMono/" | head -5
echo "  ... ($(ls -1 "$FONTS_DIR/MapleMono/" | wc -l) files total)"
echo ""
echo "Maple Mono NF:"
ls -1 "$FONTS_DIR/MapleMono-NF/" | head -5
echo "  ... ($(ls -1 "$FONTS_DIR/MapleMono-NF/" | wc -l) files total)"
echo ""
echo "Nerd Fonts Symbols Only:"
ls -1 "$FONTS_DIR/NerdFontsSymbolsOnly/"
echo ""
echo "Font cache updated. You may need to restart applications to see the new fonts."
