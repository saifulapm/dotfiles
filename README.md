# Dotfiles

My Fedora Asahi Linux setup.

## Install

```bash
curl -sL https://raw.githubusercontent.com/saifulapm/dotfiles/main/install.sh | bash
```

## Structure

```
dotfiles/
├── setup.sh          # Main setup script
├── install.sh        # Remote installer
├── copr.list         # COPR repositories
├── packages.list     # DNF packages
├── flatpak.list      # Flatpak packages
├── snap.list         # Snap packages
├── cargo.list        # Cargo packages
├── go.list           # Go packages
├── symlinks.list     # Partial symlinks (src:dest)
├── fonts/            # Custom fonts
├── scripts/          # Auto-run scripts
├── bin/              # Executables → ~/.local/bin
└── config/
    ├── */            # → ~/.config/*
    └── home/         # → ~/.*
```

## Usage

Edit the list files to add packages, then run `./setup.sh` to apply changes.

## Secrets

Secrets are encrypted with [age](https://github.com/FiloSottile/age) and stored in `secrets.age` (gitignored).

```bash
secrets init          # Create new encrypted secrets file
secrets edit          # Edit secrets (decrypt, edit, re-encrypt)
secrets get KEY       # Get a single secret value
eval "$(secrets load)" # Load all secrets as env vars
```

In configs, use environment variables:
```lua
-- Example: nvim/lua/plugins/lsp.lua
license_key = os.getenv("INTELEPHENSE_KEY")
```

Or fetch directly:
```bash
KEY=$(secrets get INTELEPHENSE_KEY)
```
