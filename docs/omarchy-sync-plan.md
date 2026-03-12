# Omarchy Sync Plan

## Overview
Sync selected features from omarchy (554 commits since Jan 26, 2026) into our dotfiles.
Adapt all `omarchy-*` naming to `nova-*` convention. Terminal = foot. Single `shell/functions` file.

## Decisions Made
- Keep single `shell/functions` file (no splitting into fns/)
- No user theme overrides (we own the repo)
- Foot as tmux terminal
- All 3 new themes (Vantablack, Miasma, White)
- Sync all background renames + new backgrounds
- Skip: terminal default change, Hyprland scripts, SDDM, menu extensions, hooks, AGENTS.md

---

## Step 1: Shell Functions & Aliases

### New functions → `shell/functions`

**Git worktrees:**
```bash
# ga <branch> — create git worktree at ../reponame-branch/ and cd into it
# gd — remove current worktree with confirmation, cd back to main
```

**SSH port forwarding:**
```bash
# fip <host> <ports...> — SSH port forward (e.g., fip server 3000 5432)
# dip <ports...> — disconnect forwarded ports
# lip — list active port forwards
```

**Tmux layouts:**
```bash
# tdl <ai> — tmux dev layout: editor + AI pane + terminal
#   ai options: c=opencode, cx=claude --dangerously-skip-permissions
# tdlm <ai> — multi-project: one tdl window per subdirectory
# tsl <count> <cmd> — tmux swarm: tile N panes running same command
```

### New aliases → `shell/aliases`
```bash
alias eff='$EDITOR "$(ff)"'        # open fzf result in editor
alias cx='claude --dangerously-skip-permissions'
alias t='tmux attach || tmux new -s Work'
```

**Also add `sff` function** (not alias — needs args):
```bash
# sff <dest> — fzf pick a file then scp to remote
```

### Source files
- Omarchy worktrees: `resources/omarchy/default/bash/fns/worktrees`
- Omarchy SSH forwarding: `resources/omarchy/default/bash/fns/ssh-port-forwarding`
- Omarchy tmux fns: `resources/omarchy/default/bash/fns/tmux`
- Omarchy aliases: `resources/omarchy/default/bash/aliases`

---

## Step 2: Tmux Integration

### New files to create
- `config/tmux/tmux.conf` — adapt from `resources/omarchy/config/tmux/tmux.conf`
  - C-Space prefix
  - vi copy mode
  - vim-tmux-navigator (Ctrl+arrow pane navigation)
  - Auto-rename windows to cwd
  - Status bar theming (integrate with our theme system)

### Package addition
- Add `tmux` to `packages.list` (if not already there)

### Niri keybinding
- Add `Super + Alt + Return` → launch `footclient tmux attach || footclient tmux new -s Work`
- Add to `config/niri/binds.kdl`

### Theme template
- Check if omarchy has a tmux theme template → if so, add `templates/tmux.conf.tpl` or similar
- Wire into `bin/theme` generate_theme()

---

## Step 3: Power Management

### New scripts → `scripts/`
- `setup-power-profiles.sh` — auto power profile switching: balanced on AC, power-saver on battery
  - Source: `resources/omarchy/install/config/powerprofilesctl-rules.sh`

### New systemd units → `config/systemd/`
- `system-sleep/unmount-fuse` — unmount FUSE before suspend (prevent silent failures)
  - Source: `resources/omarchy/default/systemd/system-sleep/unmount-fuse`
- `system-sleep/keyboard-backlight` — turn off keyboard backlight before sleep
  - Source: `resources/omarchy/default/systemd/system-sleep/keyboard-backlight`

### New bin scripts
- `bin/nova-wifi-powersave` — disable WiFi power saving on AC
  - Source: `resources/omarchy/bin/omarchy-wifi-powersave`

### New config
- Faster shutdown config → `config/systemd/system/` or via setup script
  - Source: `resources/omarchy/default/systemd/faster-shutdown.conf`

### Setup integration
- Add `scripts/setup-power.sh` that:
  - Installs power profile switching rules
  - Installs WiFi powersave udev rules
  - Copies system-sleep hooks (these need sudo, can't be symlinked to user dir)
  - Applies faster shutdown config

---

## Step 4: Battery Improvements

### New/updated bin scripts
- `bin/nova-battery-capacity` — get battery percentage
  - Source: `resources/omarchy/bin/omarchy-battery-capacity`
- `bin/nova-battery-present` — check if battery exists
  - Source: `resources/omarchy/bin/omarchy-battery-present`
- `bin/nova-battery-remaining` — update with omarchy's improved version
  - Source: `resources/omarchy/bin/omarchy-battery-remaining-time`
- `bin/nova-battery-status` — combined status string for notifications
  - Source: `resources/omarchy/bin/omarchy-battery-status`

### Update existing
- Compare our existing `bin/nova-battery-monitor` and `bin/nova-notify-battery` with omarchy equivalents
- Adopt improvements if any

---

## Step 5: Waybar Indicators

### New indicator scripts → `default/waybar/indicators/`
- `idle.sh` — shows lock icon when idle locking is disabled
  - Source: `resources/omarchy/default/waybar/indicators/idle.sh`
- `notification-silencing.sh` — shows DND icon when active
  - Source: `resources/omarchy/default/waybar/indicators/notification-silencing.sh`

### New bin scripts
- `bin/nova-toggle-notification-silencing` — toggle DND with waybar signal
  - Source: `resources/omarchy/bin/omarchy-toggle-notification-silencing`
- `bin/nova-toggle-idle-lock` — toggle idle lock (if not already exists)

### Waybar config changes
- Add `custom/idle-indicator` and `custom/dnd-indicator` modules to `config/waybar/config.jsonc`
- Add CSS for the indicators in `config/waybar/style.css`

---

## Step 6: Screen Recording Overhaul

### Update `bin/nova-cmd-screenrecord`
Changes from omarchy:
- Switch to h264 encoding (Mac-compatible sharing)
- Cap at 4K resolution
- Trim first 100ms to avoid noise
- Better preview notification that opens recording on click

### Source
- `resources/omarchy/bin/omarchy-cmd-screenrecord` (or equivalent)

---

## Step 7: Background Selector & Theme Refresh

### New bin scripts
- `bin/nova-theme-bg-set` — set specific background by name
  - Source: `resources/omarchy/bin/omarchy-theme-bg-set`
- `bin/nova-theme-refresh` — refresh theme without full re-set (re-applies current theme)
  - Simple: `theme set "$(theme current)"`

### Niri keybinding change
- `Super + Ctrl + Space` → background menu (was "next background")
- Need to implement a background picker using fuzzel (our launcher, since we don't have Walker/Elephant)
  - List backgrounds in current theme dir
  - Show in fuzzel
  - Apply selected with nova-theme-bg-set

### New bin script
- `bin/nova-bg-menu` — fuzzel-based background picker
  - Lists `themes/<current>/backgrounds/*`
  - User picks one
  - Calls `nova-theme-bg-set <name>`

---

## Step 8: Theme Sync

### Background renames (ALL shared themes)
For each theme below, rename background files to match omarchy:

| Theme | Old → New |
|-------|-----------|
| catppuccin | 1-catppuccin.png → 1-totoro.png, 2-cat-waves-mocha.png → 2-waves.png, 3-cat-blue-eye-mocha.png → 3-blue-eye.png |
| catppuccin-latte | 1-catppuccin-latte.png → 1-color-fade.png |
| ethereal | 1.jpg → 1-cosmic.jpg, 2.jpg → 2-meadow.jpg |
| everforest | 1-everforest.jpg → 1-tree-tops.jpg |
| flexoki-light | 1-flexoki-light-orb.png → 1-orb.png, 2-flexoki-light-omarchy.png → 2-omarchy.png |
| gruvbox | 1-grubox.jpg → 1-the-backwater.jpg, 2-gruvbox.jpg → 2-leaves.jpg |
| hackerman | 1.jpg → 1-synth-scape.jpg, 2.jpg → 2-geometric.jpg |
| kanagawa | (no changes) |
| matte-black | 1-matte-black.jpg → 1-dark-waters.jpg, 2-matte-black-hands.jpg → 2-dot-hands.jpg |
| nord | 1-nord.png → 1-city-view.png, 2-nord.png → 2-night-hawks.png, ADD 0-black-moon.jpg |
| osaka-jade | 1-osaka-jade-bg.jpg → 1-glowing-city.jpg, 2-osaka-jade-bg.jpg → 2-shaded-entrance.jpg, 3-osaka-jade-bg.jpg → 3-mountain-moon.jpg |
| ristretto | 1-ristretto.jpg → 1-color-curves.jpg, 2-ristretto.jpg → 2-coffee-beans.jpg, 3-ristretto.jpg → 3-industrial-moon.jpg |
| rose-pine | 1-rose-pine.jpg → 1-funky-shapes.jpg, 2-wave-light.png → 2-dot-map.png, 3-leafy-dawn-omarchy.png → 3-omarchy-plants.png |
| tokyo-night | full reorganization (see agent report), ADD 3-milad-fakurian.jpg |

### New backgrounds to copy
- `nord/backgrounds/0-black-moon.jpg` from omarchy
- `tokyo-night/backgrounds/3-milad-fakurian.jpg` from omarchy
- `tokyo-night/backgrounds/0-swirl-buck.jpg` from omarchy

### Rose-pine fix
- Add `light.mode` marker file (it's a light theme like flexoki-light)

### New themes to copy entirely from omarchy
- `themes/vantablack/` — all files (colors.toml, backgrounds/, btop.theme, etc.)
- `themes/miasma/` — all files
- `themes/white/` — all files (includes light.mode marker)

### Theme file cleanup
- Remove `chromium.theme` from themes that still have it (handled by templates now via bin/theme)
- Remove `fuzzel.ini` from themes that still have it (handled by templates now)

---

## Implementation Order
1. Shell functions & aliases (no deps)
2. Tmux (needs shell aliases)
3. Power management (standalone)
4. Battery improvements (standalone)
5. Waybar indicators (standalone)
6. Screen recording (standalone)
7. Background selector + theme refresh (needs existing theme system)
8. Theme sync (backgrounds, new themes — last because large file operations)

## Notes
- All omarchy `omarchy-*` scripts rename to `nova-*`
- Test each step independently before moving to next
- Commit after each step
