# ~/.dotfiles

Chezmoi-managed dotfiles + a Quickshell desktop shell (`shell/`) for niri on
Fedora. Three machines: MacBook Pro M2 and Mac mini M2 (Fedora Asahi Remix,
aarch64) and an Intel NUC (Fedora minimal, x86_64).

## Restore

The repo lives at github.com/saifulapm/dotfiles (private; the pre-2026-08
content survives on the `archive-pre-qshell` branch). Because the remote is
SSH-only, a fresh machine needs `~/.ssh` restored FIRST — it lives in iCloud
Drive: either `rclone config` an iCloud remote and
`rclone copy iCloud:.ssh ~/.ssh && chmod 700 ~/.ssh && chmod 600 ~/.ssh/*
&& chmod 644 ~/.ssh/*.pub`, or copy it from another machine. (The ssh
config's `UseKeychain` needs the `IgnoreUnknown UseKeychain` guard line on
Linux; the synced copy carries it.)

Then, on a fresh Fedora minimal install, from a TTY, one command:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply --source ~/.dotfiles git@github.com:saifulapm/dotfiles.git
```

That run asks which machine this is, then installs every package in
`packages/manifest.toml` (sudo prompts on the TTY), enforces
`install_weak_deps=False` in `/etc/dnf/dnf.conf`, sets up tty1 autologin,
registers the shell's file-chooser portal, installs the dev toolchain (node
via mise, pnpm via corepack, rust via rustup, Shopify CLI) and the agent CLIs
(claude, codex, copilot, pi), enables the user timers, brings up tailscaled,
fetches the fonts (pinned externals) and bootstraps the default theme.
**Reboot at the end** — autologin lands you in niri with the shell running.

### What stays manual, honestly

- `tailscale up` — interactive browser auth (the apply prints this loudly;
  the bar's tailscale widget has the same login flow).
- First login for each agent CLI: `claude`, `codex`, `copilot`.
- `rclone config` — once per remote, per machine: the iCloud remote
  (interactive Apple 2FA) and, on the Macs, a Dropbox remote (interactive
  browser OAuth; no aarch64 Dropbox client exists, rclone is the access
  path there). Session secrets live only in `~/.config/rclone/rclone.conf`,
  never in this repo. The bar's rclone widgets stay hidden until their
  remote exists — configuring it is all it takes.
- Dropbox linking, NUC only: `dropbox start` prints the login URL (the
  daemon and CLI install themselves; the Macs get nothing — no aarch64
  Dropbox exists).
- voxtype (dictation): manual binary download from
  github.com/peteonrails/voxtype/releases into `~/.local/bin`, then
  `voxtype setup --download --model base.en && voxtype setup systemd`.
  The apply finishes the systemd wiring when the binary is present.
- `~/.config/chezmoi/key.txt` (age key) — only needed if encrypted files are
  ever added to the repo; none exist today. Transport it out of band.

## Layout

- `home/` — the chezmoi source root (`.chezmoiroot`), symlink mode.
- `shell/` — the Quickshell shell (`~/.config/quickshell` symlinks here).
- `bin/` — helper scripts, on PATH via `dot_bashrc.d/10-dev.sh`.
- `packages/manifest.toml` — every package, justified, arch-aware. The single
  source of truth; the install script re-runs when it changes.
- `themes/` — one TOML per theme (22, mostly ported from omarchy).
- `templates/` — theme fan-out targets (foot, GTK, niri).
- `bench/` — measured numbers from `just bench`; performance is the product.
- `CREDITS.md` — everything borrowed from omarchy/DMS/noctalia, exactly.

## Rules

- Every package earns a manifest entry with an honest `why`.
- No polling in the shell — events, sockets, file watches; the only approved
  exceptions are the weather widget (30 min) and panels refreshing while open.
- Performance is measured (`just bench`), never assumed.
