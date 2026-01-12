#!/bin/bash

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install gum if not present
if ! command -v gum &>/dev/null; then
    echo "Installing gum..."
    sudo dnf install -y gum &>/dev/null
fi

read_list() {
    local file="$1"
    [[ -f "$file" ]] && grep -v '^#' "$file" | grep -v '^$' || true
}

header() {
    echo ""
    gum style --foreground 12 --bold "[$1]"
}

done_msg() {
    gum style --foreground 10 "  ✓ $1"
}

skip_msg() {
    gum style --foreground 11 "  ○ $1"
}

spin() {
    gum spin --spinner dot --title "$1" -- "${@:2}"
}

# Banner
echo ""
gum style --border rounded --padding "0 2" --border-foreground 14 --bold "Fedora Asahi Setup"
echo ""

# ─────────────────────────────────────────────────────────────
# COPR Repositories
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/copr.list" ]]; then
    repos=$(read_list "$DOTFILES/copr.list")
    if [[ -n "$repos" ]]; then
        header "COPR Repositories"
        count=0
        while IFS= read -r repo; do
            spin "  Enabling $repo" sudo dnf copr enable -y "$repo" 2>/dev/null || true
            ((count++))
        done <<< "$repos"
        done_msg "$count repos enabled"
    fi
fi

# ─────────────────────────────────────────────────────────────
# DNF Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/packages.list" ]]; then
    packages=$(read_list "$DOTFILES/packages.list")
    if [[ -n "$packages" ]]; then
        header "DNF Packages"
        readarray -t pkg_array <<< "$packages"
        count=${#pkg_array[@]}
        spin "  Installing $count packages" sudo dnf install -y "${pkg_array[@]}" 2>/dev/null || true
        done_msg "$count packages installed"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Fonts
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/fonts" ]]; then
    shopt -s nullglob
    fonts=("$DOTFILES/fonts"/*)
    shopt -u nullglob
    count=0
    for f in "${fonts[@]}"; do
        [[ "$(basename "$f")" != ".gitkeep" ]] && ((count++)) || true
    done
    if [[ $count -gt 0 ]]; then
        header "Fonts"
        mkdir -p ~/.local/share/fonts
        for font in "${fonts[@]}"; do
            [[ "$(basename "$font")" == ".gitkeep" ]] && continue
            name=$(basename "$font")
            cp -r "$font" ~/.local/share/fonts/
        done
        spin "  Updating font cache" fc-cache -f
        done_msg "$count fonts installed"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Cargo Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/cargo.list" ]]; then
    cargo_pkgs=$(read_list "$DOTFILES/cargo.list")
    if [[ -n "$cargo_pkgs" ]]; then
        header "Cargo Packages"
        if ! command -v cargo &>/dev/null; then
            spin "  Installing Rust" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null'
            source "$HOME/.cargo/env"
        fi
        count=0
        while IFS= read -r pkg; do
            spin "  Installing $pkg" cargo install "$pkg" 2>/dev/null || true
            ((count++))
        done <<< "$cargo_pkgs"
        done_msg "$count packages installed"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Go Packages
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/go.list" ]]; then
    go_pkgs=$(read_list "$DOTFILES/go.list")
    if [[ -n "$go_pkgs" ]]; then
        header "Go Packages"
        if ! command -v go &>/dev/null; then
            spin "  Installing Go" sudo dnf install -y golang 2>/dev/null
        fi
        if command -v go &>/dev/null; then
            count=0
            while IFS= read -r pkg; do
                name=$(basename "$pkg" | cut -d'@' -f1)
                spin "  Installing $name" go install "$pkg" 2>/dev/null || true
                ((count++))
            done <<< "$go_pkgs"
            done_msg "$count packages installed"
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────
# Config Symlinks (~/.config)
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/config" ]]; then
    shopt -s nullglob
    configs=("$DOTFILES/config"/*)
    shopt -u nullglob
    count=0
    for c in "${configs[@]}"; do
        [[ "$(basename "$c")" != "home" ]] && ((count++)) || true
    done
    if [[ $count -gt 0 ]]; then
        header "Config Symlinks"
        mkdir -p ~/.config
        for item in "${configs[@]}"; do
            name=$(basename "$item")
            [[ "$name" == "home" ]] && continue
            rm -rf "$HOME/.config/$name"
            ln -sf "$item" "$HOME/.config/$name"
            gum style --foreground 8 "  → $name"
        done
        done_msg "$count configs linked"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Home Directory Dotfiles
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/config/home" ]]; then
    shopt -s nullglob
    home_files=("$DOTFILES/config/home"/*)
    shopt -u nullglob
    if [[ ${#home_files[@]} -gt 0 ]]; then
        header "Home Dotfiles"
        count=0
        for item in "${home_files[@]}"; do
            name=$(basename "$item")
            rm -rf "$HOME/$name"
            ln -sf "$item" "$HOME/$name"
            gum style --foreground 8 "  → $name"
            ((count++))
        done
        done_msg "$count dotfiles linked"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Partial Symlinks
# ─────────────────────────────────────────────────────────────
if [[ -f "$DOTFILES/symlinks.list" ]]; then
    symlinks=$(read_list "$DOTFILES/symlinks.list")
    if [[ -n "$symlinks" ]]; then
        header "Partial Symlinks"
        count=0
        while IFS=: read -r src dest; do
            [[ -z "$src" || -z "$dest" ]] && continue
            src_path="$DOTFILES/$src"
            dest_path="$HOME/$dest"
            if [[ -e "$src_path" ]]; then
                mkdir -p "$(dirname "$dest_path")"
                rm -rf "$dest_path"
                ln -sf "$src_path" "$dest_path"
                gum style --foreground 8 "  → $dest"
                ((count++))
            fi
        done <<< "$symlinks"
        done_msg "$count symlinks created"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Custom Executables
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/bin" ]]; then
    shopt -s nullglob
    bins=("$DOTFILES/bin"/*)
    shopt -u nullglob
    count=0
    for b in "${bins[@]}"; do
        [[ -f "$b" && "$(basename "$b")" != ".gitkeep" ]] && ((count++)) || true
    done
    if [[ $count -gt 0 ]]; then
        header "Custom Executables"
        mkdir -p ~/.local/bin
        for script in "${bins[@]}"; do
            [[ -f "$script" ]] || continue
            name=$(basename "$script")
            [[ "$name" == ".gitkeep" ]] && continue
            chmod +x "$script"
            ln -sf "$script" ~/.local/bin/"$name"
            gum style --foreground 8 "  → $name"
        done
        done_msg "$count executables linked"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Custom Scripts
# ─────────────────────────────────────────────────────────────
if [[ -d "$DOTFILES/scripts" ]]; then
    shopt -s nullglob
    scripts=("$DOTFILES/scripts"/*.sh)
    shopt -u nullglob
    if [[ ${#scripts[@]} -gt 0 ]]; then
        header "Running Scripts"
        count=0
        for script in "${scripts[@]}"; do
            [[ -f "$script" ]] || continue
            name=$(basename "$script")
            chmod +x "$script"
            spin "  Running $name" "$script" || true
            ((count++))
        done
        done_msg "$count scripts completed"
    fi
fi

# ─────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────
echo ""
gum style --foreground 10 --bold "✓ Setup complete!"
echo ""
