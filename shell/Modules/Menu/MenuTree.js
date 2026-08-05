// The command menu's action tree — this file IS the menu. Edit it and the
// running shell picks the change up on the next reload.
//
// Shape mirrors omarchy's omarchy-menu.jsonc (CREDITS.md): ids are keys, a
// dotted id declares its parent ("capture.region" lives under "capture"), and
// the kind is inferred — `action` or `call` makes a row, `target` makes a
// redirect, anything else is a submenu. Declaration order is display order.
//
// Fields:
//   icon         Nerd Font glyph. MATERIAL DESIGN RANGE ONLY (U+F0001+) —
//                the FontAwesome range does not render under our font fallback.
//   label        row text
//   title        header text while the submenu is open (defaults to label)
//   aliases      extra search terms, and routes for `qs ipc call menu open <x>`
//   description  searched by whole word; shown as the row detail while filtering
//   action       shell command, run detached through `bash -lc`
//   call         handled inside the shell instead (see Menu.qml runCall)
//   target       id of another menu to open (a link row)
//   when         shell test; the row is hidden when it fails
//   checked      shell test; appends ✓ when it succeeds
//   state        in-shell boolean name that does the same (see Menu.qml stateValue)

var TREE = {
    // ------------------------------------------------------------------ root
    "apps": {
        "icon": "󰀻",
        "label": "Apps",
        "aliases": ["app", "applications", "launcher", "run"],
        "description": "Launch an installed application",
        "call": "launcher"
    },
    "theme": {
        "icon": "󰸌",
        "label": "Theme",
        "aliases": ["themes", "style", "colors", "colours", "appearance"],
        "description": "Switch the desktop theme",
        "call": "themes"
    },
    "capture": {
        "icon": "󰄀",
        "label": "Capture",
        "aliases": ["screenshot", "screenshots", "shot", "grab", "screen"]
    },
    // Omarchy files this under their Trigger submenu, next to Capture — our
    // tree hoisted Capture to the root, so Emoji sits beside it.
    "emoji": {
        "icon": "󰇵",
        "label": "Emoji",
        "aliases": ["emojis", "emoticon", "smiley", "symbols"],
        "description": "Search an emoji and copy it to the clipboard",
        "call": "emojis"
    },
    "toggle": {
        "icon": "󰔎",
        "label": "Toggle",
        "aliases": ["toggles", "switch"]
    },
    "setup": {
        "icon": "󰒓",
        "label": "Setup",
        "aliases": ["settings", "config", "configure", "preferences"]
    },
    "update": {
        "icon": "󰚰",
        "label": "Update",
        "aliases": ["upgrade", "packages", "dnf"],
        "description": "Install pending system packages",
        "when": "command -v foot",
        "action": "foot --app-id=qshell-float -e bash -lc 'sudo dnf upgrade --refresh; rm -f ~/.local/state/qshell/updates; read -r -p \"done — press enter to close\"'"
    },
    "system": {
        "icon": "󰐥",
        "label": "System",
        "aliases": ["power", "power-menu", "session"]
    },

    // --------------------------------------------------------------- capture
    "capture.region": {
        "icon": "󰩭",
        "label": "Region",
        "aliases": ["area", "selection", "crop"],
        "description": "Pick an area to screenshot",
        "when": "command -v niri",
        "action": "niri msg action screenshot"
    },
    "capture.window": {
        "icon": "󰖯",
        "label": "Window",
        "aliases": ["active"],
        "description": "Screenshot the focused window",
        "when": "command -v niri",
        "action": "niri msg action screenshot-window"
    },
    "capture.screen": {
        "icon": "󰍹",
        "label": "Screen",
        "aliases": ["display", "monitor", "fullscreen"],
        "description": "Screenshot the whole focused screen",
        "when": "command -v niri",
        "action": "niri msg action screenshot-screen"
    },

    // ---------------------------------------------------------------- toggle
    "toggle.dnd": {
        "icon": "󰂛",
        "label": "Do Not Disturb",
        "aliases": ["dnd", "notifications", "silence", "quiet"],
        "description": "Silence notification popups",
        "state": "dnd",
        "call": "dnd"
    },
    "toggle.keyboard-layout": {
        "icon": "󰌌",
        "label": "Keyboard Layout",
        "aliases": ["kb", "layout", "language", "input"],
        "description": "Switch to the next keyboard layout",
        "when": "command -v niri",
        "action": "niri msg action switch-layout next"
    },

    // ----------------------------------------------------------------- setup
    "setup.shell": {
        "icon": "󰍜",
        "label": "Shell Config",
        "aliases": ["bar", "widgets", "shell-json"],
        "description": "Edit shell.json in a terminal",
        "when": "command -v foot",
        "action": "foot --app-id=qshell-float -e \"${EDITOR:-vi}\" \"$HOME/.dotfiles/shell/shell.json\""
    },
    "setup.niri": {
        "icon": "󱂬",
        "label": "Niri Config",
        "aliases": ["compositor", "keybinds", "keybindings", "kdl"],
        "description": "Edit the niri config in a terminal",
        "when": "command -v foot",
        "action": "foot --app-id=qshell-float -e \"${EDITOR:-vi}\" \"$HOME/.dotfiles/home/dot_config/niri/config.kdl\""
    },
    "setup.themes": {
        "icon": "󰸌",
        "label": "Theme Files",
        "aliases": ["dotfiles", "tokens", "toml"],
        "description": "Open a terminal in the dotfiles theme directory",
        "when": "command -v foot",
        "action": "foot --app-id=qshell-float --working-directory=\"$HOME/.dotfiles/themes\""
    },

    // ---------------------------------------------------------------- system
    "system.lock": {
        "icon": "󰌾",
        "label": "Lock",
        "aliases": ["lockscreen", "screensaver"],
        "description": "Lock the session",
        "call": "lock"
    },
    "system.suspend": {
        "icon": "󰒲",
        "label": "Suspend",
        "aliases": ["sleep"],
        "when": "command -v systemctl",
        "action": "systemctl suspend"
    },
    "system.relaunch": {
        "icon": "󰑐",
        "label": "Relaunch Shell",
        "aliases": ["restart-shell", "reload", "qs"],
        "description": "Restart this shell process",
        // The bash child is orphaned by the pkill and survives it, so it can
        // start the replacement in a fresh session.
        "action": "pkill -x qs; sleep 0.5; exec setsid qs"
    },
    "system.exit": {
        "icon": "󰍃",
        "label": "Exit niri",
        "aliases": ["logout", "quit", "sign-out"],
        "when": "command -v niri",
        "action": "niri msg action quit --skip-confirmation"
    },
    "system.reboot": {
        "icon": "󰜉",
        "label": "Reboot",
        "aliases": ["restart"],
        "when": "command -v systemctl",
        "action": "systemctl reboot"
    },
    "system.shutdown": {
        "icon": "󰐥",
        "label": "Shutdown",
        "aliases": ["poweroff", "halt", "off"],
        "when": "command -v systemctl",
        "action": "systemctl poweroff"
    }
};
