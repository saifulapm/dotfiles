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
