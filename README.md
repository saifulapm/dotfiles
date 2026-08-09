# ~/.dotfiles

Chezmoi-managed dotfiles + a Quickshell desktop shell (`shell/`) for niri on
Fedora. Three machines: MacBook Pro M2 and Mac mini M2 (Fedora Asahi Remix,
aarch64) and an Intel NUC (Fedora minimal, x86_64).

## Restore

The repo lives at github.com/saifulapm/dotfiles — public, so never commit a
secret (the pre-2026-08 content survives on the `archive-pre-qshell` branch).
Public also means the clone needs no credentials: on a fresh Fedora install,
from a TTY, one command —

```sh
cd ~ && sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply --source ~/.dotfiles https://github.com/saifulapm/dotfiles.git
```

(The `cd ~` is load-bearing: get.chezmoi.io drops its temporary binary into
`$(pwd)/bin`, so running it elsewhere strands a stray `bin/` there.)

That run asks which machine this is, then: installs every package in
`packages/manifest.toml` (sudo prompts on the TTY; weak deps off in
`/etc/dnf/dnf.conf`; COPRs, Remi PHP SCLs and RPM Fusion ffmpeg bootstrap
themselves), sets up tty1 autologin, registers the shell's file-chooser
portal, installs the dev toolchain (node via mise, pnpm via corepack, rust
via rustup, Shopify CLI), the agent CLIs (claude, codex, copilot, pi), the
pnpm/cargo/go/composer tool sets, prebuilt binaries (watchexec, hurl,
cloudflared, stripe, ouch, usql, satty), builds the kakoune fork and the
three oma apps from source, **switches the login shell to fish**, sets up
multi-PHP (php82/83/84 beside system 8.5), on-demand podman dev services
(mysql/postgres/redis/mailpit) and `https://<project>.test` domains, applies
the chromium policy, disables suspend everywhere, opens the dufs port,
fetches fonts (pinned externals) + the theme wallpapers (from our own
saifulapm/wallpapers repo) and bootstraps the default theme.

Expect the first apply to take a while — it compiles kakoune, **Emacs 31
(from source, the longest single step)**, ~10 cargo crates and three Qt
apps, and pre-pulls ~1.5 GB of container images. sudo's timestamp expires
between the root-needing steps, so **the password prompt returns several
times across the run** — the prompts surface mid build-output, so stay near
the keyboard rather than leaving it unattended. If anything fails mid-way
(flaky network, declined sudo), **rerun `chezmoi apply` in a terminal** —
every script is idempotent and guarded, so a second pass finishes exactly
what the first one missed. That same rerun is also how the auth-gated steps
land after the logins below.

**Reboot at the end** — autologin lands you in niri with the shell running.

Housekeeping: the bootstrap drops a temporary chezmoi at `~/bin/chezmoi`;
the manifest installs the real `/usr/bin/chezmoi`, so `rm ~/bin/chezmoi`
after the first apply.

### What stays manual, honestly

- `~/.ssh` — needed for **pushing** (the https clone works without it). It
  lives in iCloud Drive: after the apply, `rclone config` the iCloud remote,
  then `rclone copy iCloud:.ssh ~/.ssh && chmod 700 ~/.ssh && chmod 600
  ~/.ssh/* && chmod 644 ~/.ssh/*.pub`. Flip the remote with
  `git -C ~/.dotfiles remote set-url origin
  git@github.com:saifulapm/dotfiles.git` — the first ssh connect asks to
  accept GitHub's host key (the ssh config routes github.com via
  ssh.github.com:443; its `UseKeychain` line needs the synced
  `IgnoreUnknown UseKeychain` guard on Linux, which the iCloud copy carries).
  `~/.config/emacs` is the same story — the apply clones saifulapm/emacs.d
  over https; `git -C ~/.config/emacs remote set-url origin
  git@github.com:saifulapm/emacs.d.git` before pushing from it.
- `tailscale up` — interactive browser auth (the apply prints this loudly;
  the bar's tailscale widget has the same login flow).
- `gh auth login` — once per account: saifulapm (personal), Cool9977 (work),
  saiful408 (main). The gh aliases switch between them with
  `gh auth switch`. Then rerun `chezmoi apply` so the gh extensions install.
- First login for each agent CLI: `claude`, `codex`, `copilot`.
- `rclone config` — once per remote, per machine: the iCloud remote
  (interactive Apple 2FA) and the Dropbox remote (interactive browser
  OAuth). rclone is the ONE Dropbox path on every machine (2026-08-10): the
  proprietary daemon the NUC used to run is gone, so all three boxes are set
  up the same way and no aarch64/x86_64 split remains. Session secrets live
  only in `~/.config/rclone/rclone.conf`, never in this repo. The bar's
  rclone widgets stay hidden and qshell-sync skips quietly until their remote
  exists — configuring it is all it takes.
- cloudflared tunnel credentials — `~/.cloudflared/config.dev.yaml` is
  managed, but `cert.pem` (a PEM private key) and the tunnel's
  `<uuid>.json` (AccountTag + TunnelSecret) are secrets and stay out of the
  repo. Restore them like `~/.ssh`:
  `rclone copy iCloud:.dotfiles/home/.cloudflared ~/.cloudflared --include
  cert.pem --include '*.json'` then `chmod 600 ~/.cloudflared/cert.pem
  ~/.cloudflared/*.json`. Without them the tunnel will not start.
- `~/.config/fish/conf.d/99-local.fish` — machine-local API keys
  (CONTEXT7_API_KEY, …), deliberately unmanaged because the repo is public.
  Copy it from another machine or re-create it; fish sources it only if it
  exists, so nothing breaks without it.
- intelephense licence — the paid key's only backup sits in
  `iCloud:.dotfiles/config/zed/settings.json` (zed itself was rejected for
  this desktop). Place it in `~/intelephense/licence.txt` for the language
  server to pick up premium features.
- voxtype (dictation): manual binary download from
  github.com/peteonrails/voxtype/releases into `~/.local/bin`, then
  `voxtype setup --download --model base.en && voxtype setup systemd`.
  The apply finishes the systemd wiring when the binary is present.
- `~/.config/chezmoi/key.txt` (age key) — only needed if encrypted files are
  ever added to the repo; none exist today. Transport it out of band.

## Layout

- `home/` — the chezmoi source root (`.chezmoiroot`), symlink mode.
- `shell/` — the Quickshell shell (`~/.config/quickshell` symlinks here).
- `bin/` — helper scripts, on PATH via `fish/conf.d/00-env.fish` (and
  `dot_bashrc.d/10-dev.sh` for bash contexts).
- `packages/manifest.toml` — every package, justified, arch-aware. The single
  source of truth; the install script re-runs when it changes.
- `themes/` — one TOML per theme (22, mostly ported from omarchy). The
  matching wallpapers live in our own `saifulapm/wallpapers` repo and land in
  `~/.local/share/qshell/backgrounds` (plus your own `~/Pictures/Wallpapers`).
- `templates/` — theme fan-out targets (foot, GTK, niri, yazi, tmux, oma).
- `bench/` — measured numbers from `just bench`; performance is the product.
- `CREDITS.md` — everything borrowed from omarchy/DMS/noctalia, exactly.

## Rules

- Every package earns a manifest entry with an honest `why`.
- No polling in the shell — events, sockets, file watches; the only approved
  exceptions are the weather widget (30 min) and panels refreshing while open.
- Performance is measured (`just bench`), never assumed.
